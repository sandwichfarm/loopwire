use std::{
    env, fs, io,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

struct BackgroundBinaryStatus {
    binary: PathBuf,
    available: bool,
    note: Option<String>,
}

#[tauri::command]
fn run_audio_command(
    command: String,
    args: Vec<String>,
    timeout_ms: Option<u64>,
) -> Result<String, String> {
    if !is_allowed_audio_command(&command, &args) {
        return Err(format!(
            "audio command is not allowed: {} {}",
            command,
            args.join(" ")
        ));
    }

    let timeout = Duration::from_millis(timeout_ms.unwrap_or(5_000).clamp(250, 30_000));
    let mut child = match Command::new(&command)
        .args(&args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => {
            return Ok(command_result_json(
                &command,
                &args,
                127,
                "",
                &error.to_string(),
                Some("missing"),
            ));
        }
    };

    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_status)) => break,
            Ok(None) if started.elapsed() <= timeout => thread::sleep(Duration::from_millis(10)),
            Ok(None) => {
                let _ = child.kill();
                let output = child
                    .wait_with_output()
                    .map_err(|error| error.to_string())?;
                return Ok(command_result_json(
                    &command,
                    &args,
                    124,
                    &String::from_utf8_lossy(&output.stdout),
                    &String::from_utf8_lossy(&output.stderr),
                    Some("timeout"),
                ));
            }
            Err(error) => return Err(error.to_string()),
        }
    }

    let output = child
        .wait_with_output()
        .map_err(|error| error.to_string())?;
    Ok(command_result_json(
        &command,
        &args,
        output.status.code().unwrap_or(1),
        &String::from_utf8_lossy(&output.stdout),
        &String::from_utf8_lossy(&output.stderr),
        None,
    ))
}

#[tauri::command]
fn manage_startup(action: String) -> Result<String, String> {
    let path = autostart_path()?;
    let background_path = background_startup_path()?;
    let binary = current_binary_path()?;
    let state = state_path()?;

    match action.as_str() {
        "status" => Ok(startup_status_json(
            &path,
            &binary,
            "Startup status checked.",
            true,
        )),
        "install" => {
            install_startup_entry(&path, &binary).map_err(|error| error.to_string())?;
            Ok(startup_status_json(
                &path,
                &binary,
                "Loopwire will start with your desktop session.",
                true,
            ))
        }
        "uninstall" => {
            uninstall_startup_entry(&path).map_err(|error| error.to_string())?;
            Ok(startup_status_json(
                &path,
                &binary,
                "Loopwire desktop autostart was removed.",
                true,
            ))
        }
        "background_status" => {
            let status = background_binary_status(&binary);
            Ok(background_startup_status_json(
                &background_path,
                &status.binary,
                "Background restore status checked.",
                status.available,
                status.note.as_deref(),
            ))
        }
        "background_install" => {
            let status = background_binary_status(&binary);
            if !status.available {
                return Ok(background_startup_status_json(
                    &background_path,
                    &status.binary,
                    "Background restore enable was blocked.",
                    false,
                    status.note.as_deref(),
                ));
            }

            install_background_startup_entry(&background_path, &status.binary, &state)
                .map_err(|error| error.to_string())?;
            Ok(background_startup_status_json(
                &background_path,
                &status.binary,
                "Loopwire will restore audio through a user systemd unit.",
                true,
                None,
            ))
        }
        "background_uninstall" => {
            uninstall_background_startup_entry(&background_path)
                .map_err(|error| error.to_string())?;
            let status = background_binary_status(&binary);
            Ok(background_startup_status_json(
                &background_path,
                &status.binary,
                "Loopwire background restore was removed.",
                status.available,
                status.note.as_deref(),
            ))
        }
        _ => Err(format!("unsupported startup action: {action}")),
    }
}

#[tauri::command]
fn read_state() -> Result<String, String> {
    let path = state_path()?;

    match fs::read_to_string(&path) {
        Ok(content) => Ok(content),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(String::new()),
        Err(error) => Err(format!("could not read Loopwire state: {error}")),
    }
}

#[tauri::command]
fn write_state(raw: String) -> Result<String, String> {
    let path = state_path()?;
    write_state_file(&path, &raw).map_err(|error| error.to_string())?;
    Ok(path.display().to_string())
}

fn command_result_json(
    command: &str,
    args: &[String],
    exit_code: i32,
    stdout: &str,
    stderr: &str,
    error_code: Option<&str>,
) -> String {
    let args_json = args
        .iter()
        .map(|arg| format!("\"{}\"", escape_json(arg)))
        .collect::<Vec<_>>()
        .join(",");
    let error_code_json = error_code
        .map(|code| format!(",\"errorCode\":\"{}\"", escape_json(code)))
        .unwrap_or_default();

    format!(
        "{{\"command\":\"{}\",\"args\":[{}],\"exitCode\":{},\"stdout\":\"{}\",\"stderr\":\"{}\"{}}}",
        escape_json(command),
        args_json,
        exit_code,
        escape_json(stdout),
        escape_json(stderr),
        error_code_json
    )
}

fn is_allowed_audio_command(command: &str, args: &[String]) -> bool {
    match command {
        "aplay" => args_match(args, &["-l"]),
        "arecord" => args_match(args, &["-l"]),
        "jack_connect" | "jack_disconnect" => {
            args.len() == 2 && args.iter().all(|arg| is_port_name(arg))
        }
        "jack_lsp" => args.is_empty() || args_match(args, &["-c"]) || args_match(args, &["-p"]),
        "pactl" => is_allowed_pactl_args(args),
        "pw-cli" => is_allowed_pw_cli_args(args),
        "pw-link" => is_allowed_pw_link_args(args),
        "wpctl" => args_match(args, &["status"]),
        _ => false,
    }
}

fn is_allowed_pactl_args(args: &[String]) -> bool {
    if args_match(args, &["info"])
        || args_match(args, &["list", "sink-inputs"])
        || args_match(args, &["list", "short", "modules"])
        || args_match(args, &["list", "short", "sinks"])
    {
        return true;
    }

    match args.first().map(String::as_str) {
        Some("load-module") => is_allowed_pactl_load_module(args),
        Some("move-sink-input") => args.len() == 3 && args[1..].iter().all(|arg| is_name_arg(arg)),
        Some("set-sink-input-mute") => {
            args.len() == 3 && is_name_arg(&args[1]) && matches!(args[2].as_str(), "0" | "1")
        }
        Some("set-sink-input-volume") => {
            args.len() == 3 && is_name_arg(&args[1]) && is_percent_arg(&args[2])
        }
        Some("unload-module") => args.len() == 2 && is_name_arg(&args[1]),
        _ => false,
    }
}

fn is_allowed_pactl_load_module(args: &[String]) -> bool {
    if args.len() == 5 && args.get(1).map(String::as_str) == Some("module-loopback") {
        return args[2].starts_with("source=")
            && args[3].starts_with("sink=")
            && args[4] == "latency_msec=20"
            && args[2..4].iter().all(|arg| is_assignment_arg(arg));
    }

    args.len() == 5
        && args.get(1).map(String::as_str) == Some("module-null-sink")
        && args[2].starts_with("sink_name=")
        && args[3].starts_with("channels=")
        && args[4].starts_with("sink_properties=device.description=")
        && args[2..].iter().all(|arg| is_assignment_arg(arg))
}

fn is_allowed_pw_cli_args(args: &[String]) -> bool {
    if args_match(args, &["--version"])
        || args_match(args, &["info", "0"])
        || args_match(args, &["list-objects", "Node"])
    {
        return true;
    }

    match args.first().map(String::as_str) {
        Some("create-node") => {
            args.len() == 3
                && args[1] == "adapter"
                && args[2].starts_with("{ factory.name=support.null-audio-sink ")
                && args[2].contains("media.class=Audio/Sink")
                && has_no_control_chars(&args[2])
        }
        Some("destroy") => args.len() == 2 && is_name_arg(&args[1]),
        _ => false,
    }
}

fn is_allowed_pw_link_args(args: &[String]) -> bool {
    if args_match(args, &["-o"]) || args_match(args, &["-i"]) || args_match(args, &["-l"]) {
        return true;
    }

    if args.len() == 3 && args[0] == "-d" {
        return args[1..].iter().all(|arg| is_port_name(arg));
    }

    args.len() == 2 && args.iter().all(|arg| is_port_name(arg))
}

fn args_match(args: &[String], expected: &[&str]) -> bool {
    args.len() == expected.len()
        && args
            .iter()
            .zip(expected.iter())
            .all(|(actual, expected)| actual == expected)
}

fn is_assignment_arg(value: &str) -> bool {
    value.contains('=') && has_no_control_chars(value)
}

fn is_name_arg(value: &str) -> bool {
    !value.is_empty() && !value.starts_with('-') && has_no_control_chars(value)
}

fn is_percent_arg(value: &str) -> bool {
    let Some(number) = value.strip_suffix('%') else {
        return false;
    };

    !number.is_empty() && number.chars().all(|character| character.is_ascii_digit())
}

fn is_port_name(value: &str) -> bool {
    is_name_arg(value) && value.contains(':')
}

fn has_no_control_chars(value: &str) -> bool {
    !value.chars().any(char::is_control)
}

fn autostart_path() -> Result<PathBuf, String> {
    Ok(config_home()?.join("autostart").join("loopwire.desktop"))
}

fn background_startup_path() -> Result<PathBuf, String> {
    Ok(systemd_user_dir()?.join("loopwire.service"))
}

fn systemd_user_dir() -> Result<PathBuf, String> {
    match env::var_os("LOOPWIRE_SYSTEMD_USER_DIR") {
        Some(value) if !value.is_empty() => Ok(PathBuf::from(value)),
        _ => Ok(config_home()?.join("systemd").join("user")),
    }
}

fn state_path() -> Result<PathBuf, String> {
    Ok(config_home()?.join("loopwire").join("state.json"))
}

fn config_home() -> Result<PathBuf, String> {
    match env::var_os("XDG_CONFIG_HOME") {
        Some(value) if !value.is_empty() => Ok(PathBuf::from(value)),
        _ => match env::var_os("HOME") {
            Some(value) if !value.is_empty() => Ok(PathBuf::from(value).join(".config")),
            _ => Err(
                "HOME or XDG_CONFIG_HOME is required for user-scoped Loopwire files".to_string(),
            ),
        },
    }
}

fn current_binary_path() -> Result<PathBuf, String> {
    env::current_exe().map_err(|error| format!("could not resolve Loopwire executable: {error}"))
}

fn background_binary_path(current_binary: &Path) -> Result<PathBuf, String> {
    match env::var_os("LOOPWIRE_BACKGROUND_BINARY") {
        Some(value) if !value.is_empty() => return Ok(PathBuf::from(value)),
        _ => {}
    }

    resolve_background_binary_path(current_binary)
}

fn background_binary_status(current_binary: &Path) -> BackgroundBinaryStatus {
    match background_binary_path(current_binary) {
        Ok(binary) => match probe_background_binary(current_binary, &binary) {
            Ok(()) => BackgroundBinaryStatus {
                binary,
                available: true,
                note: None,
            },
            Err(error) => BackgroundBinaryStatus {
                binary,
                available: false,
                note: Some(error),
            },
        },
        Err(error) => BackgroundBinaryStatus {
            binary: current_binary.to_path_buf(),
            available: false,
            note: Some(error),
        },
    }
}

fn resolve_background_binary_path(current_binary: &Path) -> Result<PathBuf, String> {
    if current_binary.file_name().and_then(|name| name.to_str()) != Some("loopwire-gui") {
        return Ok(current_binary.to_path_buf());
    }

    for candidate in packaged_launcher_candidates(current_binary) {
        if candidate.is_file() {
            return Ok(candidate);
        }
    }

    Err(
        "could not locate the Loopwire background restore launcher for this GUI binary; \
        install a packaged loopwire launcher or set LOOPWIRE_BACKGROUND_BINARY"
            .to_string(),
    )
}

fn packaged_launcher_candidates(current_binary: &Path) -> Vec<PathBuf> {
    let Some(libexec_app_dir) = current_binary.parent() else {
        return Vec::new();
    };
    let Some(libexec_parent) = libexec_app_dir.parent() else {
        return Vec::new();
    };
    let Some(prefix_or_archive_root) = libexec_parent.parent() else {
        return Vec::new();
    };

    match libexec_parent.file_name().and_then(|name| name.to_str()) {
        Some("libexec") => vec![prefix_or_archive_root.join("loopwire")],
        Some("lib") => vec![prefix_or_archive_root.join("bin").join("loopwire")],
        _ => Vec::new(),
    }
}

fn probe_background_binary(current_binary: &Path, binary: &Path) -> Result<(), String> {
    if !should_probe_background_binary(current_binary) {
        return Ok(());
    }

    let mut child = Command::new(binary)
        .args(["--background", "--help"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("background launcher preflight could not start: {error}"))?;

    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_status)) => {
                let output = child.wait_with_output().map_err(|error| {
                    format!("background launcher preflight could not read output: {error}")
                })?;

                if output.status.success() {
                    return Ok(());
                }

                return Err(format!(
                    "background launcher preflight failed with exit code {}: {}",
                    output.status.code().unwrap_or(1),
                    compact_command_output(&output.stdout, &output.stderr)
                ));
            }
            Ok(None) if started.elapsed() <= Duration::from_millis(2_000) => {
                thread::sleep(Duration::from_millis(10));
            }
            Ok(None) => {
                let _ = child.kill();
                let output = child.wait_with_output().map_err(|error| {
                    format!("background launcher preflight timed out and output could not be read: {error}")
                })?;

                return Err(format!(
                    "background launcher preflight timed out: {}",
                    compact_command_output(&output.stdout, &output.stderr)
                ));
            }
            Err(error) => {
                return Err(format!("background launcher preflight failed: {error}"));
            }
        }
    }
}

fn should_probe_background_binary(current_binary: &Path) -> bool {
    env::var_os("LOOPWIRE_BACKGROUND_BINARY")
        .map(|value| !value.is_empty())
        .unwrap_or(false)
        || current_binary.file_name().and_then(|name| name.to_str()) == Some("loopwire-gui")
}

fn compact_command_output(stdout: &[u8], stderr: &[u8]) -> String {
    let stderr = String::from_utf8_lossy(stderr);
    let stdout = String::from_utf8_lossy(stdout);
    let raw = if !stderr.trim().is_empty() {
        stderr.trim()
    } else {
        stdout.trim()
    };
    let compact = raw.split_whitespace().collect::<Vec<_>>().join(" ");

    if compact.is_empty() {
        "no output".to_string()
    } else {
        compact.chars().take(240).collect()
    }
}

fn install_startup_entry(path: &Path, binary: &Path) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    fs::write(path, render_desktop_entry(binary))?;
    set_readable_permissions(path)
}

fn install_background_startup_entry(
    path: &Path,
    binary: &Path,
    state_path: &Path,
) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    fs::write(path, render_background_service(binary, state_path))?;
    set_readable_permissions(path)?;
    enable_background_startup_link(path)
}

fn write_state_file(path: &Path, raw: &str) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    fs::write(path, raw)?;
    set_readable_permissions(path)
}

fn uninstall_startup_entry(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn uninstall_background_startup_entry(path: &Path) -> io::Result<()> {
    remove_background_startup_link(path)?;

    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn background_wants_link(path: &Path) -> io::Result<PathBuf> {
    let parent = path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "missing systemd user directory",
        )
    })?;

    Ok(parent.join("default.target.wants").join("loopwire.service"))
}

fn enable_background_startup_link(path: &Path) -> io::Result<()> {
    let link = background_wants_link(path)?;

    if let Some(parent) = link.parent() {
        fs::create_dir_all(parent)?;
    }

    match fs::remove_file(&link) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::symlink;

        symlink(path, &link)
    }

    #[cfg(not(unix))]
    {
        fs::copy(path, &link).map(|_| ())
    }
}

fn remove_background_startup_link(path: &Path) -> io::Result<()> {
    let link = background_wants_link(path)?;

    match fs::remove_file(link) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn set_readable_permissions(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        fs::set_permissions(path, fs::Permissions::from_mode(0o644))
    }

    #[cfg(not(unix))]
    {
        let _ = path;
        Ok(())
    }
}

fn render_desktop_entry(binary: &Path) -> String {
    format!(
        "[Desktop Entry]\n\
        Type=Application\n\
        Name=Loopwire\n\
        Comment=Start Loopwire when your desktop session starts\n\
        Exec=\"{}\"\n\
        Terminal=false\n\
        Categories=Audio;Utility;\n\
        X-GNOME-Autostart-enabled=true\n",
        escape_desktop_exec(binary)
    )
}

fn render_background_service(binary: &Path, state_path: &Path) -> String {
    format!(
        "[Unit]\n\
        Description=Loopwire audio routing restore\n\
        After=graphical-session.target pipewire.service pipewire-pulse.service wireplumber.service\n\
        Wants=pipewire.service wireplumber.service\n\
        \n\
        [Service]\n\
        Type=simple\n\
        ExecStart=\"{}\" --background --state-file \"{}\" --mode live\n\
        Restart=on-failure\n\
        RestartSec=2\n\
        \n\
        [Install]\n\
        WantedBy=default.target\n",
        escape_desktop_exec(binary),
        escape_desktop_exec(state_path)
    )
}

fn startup_status_json(path: &Path, binary: &Path, message: &str, available: bool) -> String {
    let enabled = path.is_file();

    format!(
        "{{\"enabled\":{},\"available\":{},\"path\":\"{}\",\"binary\":\"{}\",\"message\":\"{}\"}}",
        if enabled { "true" } else { "false" },
        if available { "true" } else { "false" },
        escape_json(&path.display().to_string()),
        escape_json(&binary.display().to_string()),
        escape_json(message)
    )
}

fn background_startup_status_json(
    path: &Path,
    binary: &Path,
    message: &str,
    available: bool,
    unavailable_note: Option<&str>,
) -> String {
    let enabled = path.is_file()
        && background_wants_link(path)
            .map(|link| link.exists())
            .unwrap_or(false);

    startup_status_json(
        path,
        binary,
        &message_for_background_status(enabled, available, message, unavailable_note),
        available,
    )
}

fn message_for_background_status(
    enabled: bool,
    available: bool,
    message: &str,
    unavailable_note: Option<&str>,
) -> String {
    if !available {
        let suffix = unavailable_note
            .filter(|note| !note.is_empty())
            .map(|note| format!(" {note}"))
            .unwrap_or_default();
        let prefix = if enabled {
            "Background restore is installed, but blocked"
        } else if message.contains("removed") {
            "Background restore was removed; enable is blocked"
        } else {
            "Background restore is blocked"
        };

        return format!("{prefix}: background launcher is unavailable.{suffix}");
    }

    if enabled {
        message.to_string()
    } else {
        "Background restore is off.".to_string()
    }
}

fn escape_desktop_exec(value: &Path) -> String {
    value
        .display()
        .to_string()
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "")
        .replace('\r', "")
}

fn escape_json(value: &str) -> String {
    value
        .chars()
        .flat_map(|character| match character {
            '"' => "\\\"".chars().collect::<Vec<_>>(),
            '\\' => "\\\\".chars().collect::<Vec<_>>(),
            '\n' => "\\n".chars().collect::<Vec<_>>(),
            '\r' => "\\r".chars().collect::<Vec<_>>(),
            '\t' => "\\t".chars().collect::<Vec<_>>(),
            '\u{08}' => "\\b".chars().collect::<Vec<_>>(),
            '\u{0c}' => "\\f".chars().collect::<Vec<_>>(),
            character if character.is_control() => {
                format!("\\u{:04x}", character as u32).chars().collect()
            }
            character => vec![character],
        })
        .collect()
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            run_audio_command,
            manage_startup,
            read_state,
            write_state
        ])
        .run(tauri::generate_context!())
        .expect("failed to run Loopwire desktop shell");
}

#[cfg(test)]
mod tests {
    use super::{
        background_binary_status, background_startup_status_json, install_background_startup_entry,
        install_startup_entry, is_allowed_audio_command, render_background_service,
        render_desktop_entry, resolve_background_binary_path, startup_status_json,
        uninstall_background_startup_entry, uninstall_startup_entry, write_state_file,
    };
    use std::{
        fs,
        path::{Path, PathBuf},
        sync::atomic::{AtomicU64, Ordering},
        time::{SystemTime, UNIX_EPOCH},
    };

    static TEMP_DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn allows_expected_audio_probe_commands() {
        for (command, args) in [
            ("aplay", vec!["-l"]),
            ("arecord", vec!["-l"]),
            ("jack_lsp", vec![]),
            ("jack_lsp", vec!["-c"]),
            ("jack_lsp", vec!["-p"]),
            ("pactl", vec!["info"]),
            ("pactl", vec!["list", "short", "modules"]),
            ("pactl", vec!["list", "short", "sinks"]),
            ("pactl", vec!["list", "sink-inputs"]),
            ("pw-cli", vec!["--version"]),
            ("pw-cli", vec!["info", "0"]),
            ("pw-cli", vec!["list-objects", "Node"]),
            ("pw-link", vec!["-o"]),
            ("pw-link", vec!["-i"]),
            ("pw-link", vec!["-l"]),
            ("wpctl", vec!["status"]),
        ] {
            assert!(allows(command, &args), "{command} {args:?}");
        }
    }

    #[test]
    fn allows_expected_audio_mutation_commands() {
        let pipewire_props = concat!(
            "{ factory.name=support.null-audio-sink node.name=\"loopwire_program\" ",
            "media.class=Audio/Sink }"
        );

        for (command, args) in [
            (
                "pactl",
                vec![
                    "load-module",
                    "module-null-sink",
                    "sink_name=loopwire_program",
                    "channels=2",
                    "sink_properties=device.description=loopwire_program",
                ],
            ),
            (
                "pactl",
                vec![
                    "load-module",
                    "module-loopback",
                    "source=loopwire_program.monitor",
                    "sink=alsa_output.headphones",
                    "latency_msec=20",
                ],
            ),
            ("pactl", vec!["move-sink-input", "44", "loopwire_program"]),
            ("pactl", vec!["set-sink-input-mute", "44", "1"]),
            ("pactl", vec!["set-sink-input-volume", "44", "86%"]),
            ("pactl", vec!["unload-module", "12"]),
            ("pw-cli", vec!["create-node", "adapter", pipewire_props]),
            ("pw-cli", vec!["destroy", "99"]),
            (
                "pw-link",
                vec![
                    "alsa_input.studio:capture_FL",
                    "loopwire_program:playback_FL",
                ],
            ),
            (
                "pw-link",
                vec![
                    "-d",
                    "alsa_input.studio:capture_FL",
                    "loopwire_program:playback_FL",
                ],
            ),
            (
                "jack_connect",
                vec!["studio_mic:capture_1", "loopwire_program:playback_1"],
            ),
            (
                "jack_disconnect",
                vec!["studio_mic:capture_1", "loopwire_program:playback_1"],
            ),
        ] {
            assert!(allows(command, &args), "{command} {args:?}");
        }
    }

    #[test]
    fn rejects_audio_command_argument_shapes_outside_loopwire_contract() {
        for (command, args) in [
            ("sh", vec!["-c", "pactl info"]),
            ("pactl", vec!["upload-sample", "/tmp/sample.wav"]),
            ("pactl", vec!["set-default-sink", "alsa_output.headphones"]),
            ("pactl", vec!["set-sink-input-mute", "44", "toggle"]),
            ("pactl", vec!["set-sink-input-volume", "44", "86"]),
            ("pw-cli", vec!["dump"]),
            ("pw-cli", vec!["create-node", "adapter", "factory.name=bad"]),
            ("pw-link", vec!["--help"]),
            (
                "pw-link",
                vec!["-d", "missing-colon", "loopwire_program:playback_FL"],
            ),
            ("jack_lsp", vec!["--help"]),
            (
                "jack_connect",
                vec!["--help", "loopwire_program:playback_1"],
            ),
            ("wpctl", vec!["set-volume", "@DEFAULT_AUDIO_SINK@", "0"]),
        ] {
            assert!(!allows(command, &args), "{command} {args:?}");
        }
    }

    #[test]
    fn renders_xdg_desktop_autostart_entry() {
        let entry = render_desktop_entry(Path::new("/tmp/Loopwire App"));

        assert!(entry.contains("Type=Application"));
        assert!(entry.contains("Name=Loopwire"));
        assert!(entry.contains("Exec=\"/tmp/Loopwire App\""));
        assert!(entry.contains("X-GNOME-Autostart-enabled=true"));
    }

    #[test]
    fn renders_background_restore_systemd_unit() {
        let unit = render_background_service(
            Path::new("/tmp/Loopwire App"),
            Path::new("/tmp/config/loopwire/state.json"),
        );

        assert!(unit.contains("Description=Loopwire audio routing restore"));
        assert!(
            unit.contains(
                "ExecStart=\"/tmp/Loopwire App\" --background --state-file \"/tmp/config/loopwire/state.json\" --mode live"
            )
        );
        assert!(unit.contains("WantedBy=default.target"));
    }

    #[test]
    fn keeps_background_capable_binary_for_restore_unit() {
        let binary = Path::new("/tmp/loopwire");

        assert_eq!(
            resolve_background_binary_path(binary).expect("resolve binary"),
            binary
        );
    }

    #[test]
    fn resolves_archive_launcher_for_packaged_gui_binary() {
        let temp_dir = unique_temp_dir();
        let launcher = temp_dir.join("loopwire");
        let gui = temp_dir.join("libexec/loopwire/loopwire-gui");

        fs::create_dir_all(gui.parent().expect("gui parent")).expect("create gui parent");
        fs::write(&launcher, "").expect("write launcher");
        fs::write(&gui, "").expect("write gui");

        assert_eq!(
            resolve_background_binary_path(&gui).expect("resolve archive launcher"),
            launcher
        );

        let _ = fs::remove_dir_all(temp_dir);
    }

    #[test]
    fn resolves_installed_launcher_for_packaged_gui_binary() {
        let temp_dir = unique_temp_dir();
        let launcher = temp_dir.join("bin/loopwire");
        let gui = temp_dir.join("lib/loopwire/loopwire-gui");

        fs::create_dir_all(launcher.parent().expect("launcher parent"))
            .expect("create launcher parent");
        fs::create_dir_all(gui.parent().expect("gui parent")).expect("create gui parent");
        fs::write(&launcher, "").expect("write launcher");
        fs::write(&gui, "").expect("write gui");

        assert_eq!(
            resolve_background_binary_path(&gui).expect("resolve installed launcher"),
            launcher
        );

        let _ = fs::remove_dir_all(temp_dir);
    }

    #[test]
    fn rejects_packaged_gui_binary_without_background_launcher() {
        let temp_dir = unique_temp_dir();
        let gui = temp_dir.join("lib/loopwire/loopwire-gui");

        fs::create_dir_all(gui.parent().expect("gui parent")).expect("create gui parent");
        fs::write(&gui, "").expect("write gui");

        let error = resolve_background_binary_path(&gui).expect_err("missing launcher should fail");

        assert!(error.contains("could not locate the Loopwire background restore launcher"));

        let _ = fs::remove_dir_all(temp_dir);
    }

    #[test]
    fn reports_missing_background_launcher_as_unavailable_status() {
        let temp_dir = unique_temp_dir();
        let gui = temp_dir.join("lib/loopwire/loopwire-gui");

        fs::create_dir_all(gui.parent().expect("gui parent")).expect("create gui parent");
        fs::write(&gui, "").expect("write gui");

        let status = background_binary_status(&gui);

        assert!(!status.available);
        assert_eq!(status.binary, gui);
        assert!(
            status
                .note
                .expect("status note")
                .contains("could not locate the Loopwire background restore launcher")
        );

        let _ = fs::remove_dir_all(temp_dir);
    }

    #[cfg(unix)]
    #[test]
    fn reports_packaged_background_launcher_preflight_failure() {
        let temp_dir = unique_temp_dir();
        let launcher = temp_dir.join("bin/loopwire");
        let gui = temp_dir.join("lib/loopwire/loopwire-gui");

        write_executable(
            &launcher,
            "#!/usr/bin/env sh\n\
            echo 'loopwire: background restore requires node on PATH' >&2\n\
            exit 127\n",
        );
        fs::create_dir_all(gui.parent().expect("gui parent")).expect("create gui parent");
        fs::write(&gui, "").expect("write gui");

        let status = background_binary_status(&gui);

        assert!(!status.available);
        assert_eq!(status.binary, launcher);
        let note = status.note.expect("status note");
        assert!(note.contains("background launcher preflight failed with exit code 127"));
        assert!(note.contains("requires node on PATH"));

        let _ = fs::remove_dir_all(temp_dir);
    }

    #[cfg(unix)]
    #[test]
    fn reports_packaged_background_launcher_preflight_success() {
        let temp_dir = unique_temp_dir();
        let launcher = temp_dir.join("bin/loopwire");
        let gui = temp_dir.join("lib/loopwire/loopwire-gui");

        write_executable(
            &launcher,
            "#!/usr/bin/env sh\n\
            if [ \"${1:-}\" = '--background' ] && [ \"${2:-}\" = '--help' ]; then\n\
              exit 0\n\
            fi\n\
            exit 2\n",
        );
        fs::create_dir_all(gui.parent().expect("gui parent")).expect("create gui parent");
        fs::write(&gui, "").expect("write gui");

        let status = background_binary_status(&gui);

        assert!(status.available);
        assert_eq!(status.binary, launcher);
        assert!(status.note.is_none());

        let _ = fs::remove_dir_all(temp_dir);
    }

    #[test]
    fn installs_and_removes_user_autostart_entry() {
        let temp_dir = unique_temp_dir();
        let path = temp_dir.join("autostart/loopwire.desktop");
        let binary = Path::new("/tmp/loopwire-test");

        install_startup_entry(&path, binary).expect("install autostart entry");
        let installed = fs::read_to_string(&path).expect("read installed entry");
        assert!(installed.contains("Exec=\"/tmp/loopwire-test\""));
        assert!(startup_status_json(&path, binary, "checked", true).contains("\"enabled\":true"));
        assert!(startup_status_json(&path, binary, "checked", true).contains("\"available\":true"));

        uninstall_startup_entry(&path).expect("uninstall autostart entry");
        assert!(!path.exists());
        assert!(startup_status_json(&path, binary, "checked", true).contains("\"enabled\":false"));

        let _ = fs::remove_dir_all(temp_dir);
    }

    #[test]
    fn installs_and_removes_background_restore_unit() {
        let temp_dir = unique_temp_dir();
        let path = temp_dir.join("systemd/user/loopwire.service");
        let binary = Path::new("/tmp/loopwire-test");
        let state = temp_dir.join("loopwire/state.json");

        install_background_startup_entry(&path, binary, &state).expect("install background unit");
        let installed = fs::read_to_string(&path).expect("read background unit");
        assert!(installed.contains("ExecStart=\"/tmp/loopwire-test\" --background"));
        assert!(installed.contains("--mode live"));
        assert!(
            background_startup_status_json(&path, binary, "checked", true, None)
                .contains("\"enabled\":true")
        );
        assert!(
            background_startup_status_json(&path, binary, "checked", true, None)
                .contains("\"available\":true")
        );

        uninstall_background_startup_entry(&path).expect("uninstall background unit");
        assert!(!path.exists());
        assert!(
            background_startup_status_json(&path, binary, "checked", true, None)
                .contains("\"enabled\":false")
        );
        assert!(
            background_startup_status_json(
                &path,
                binary,
                "checked",
                false,
                Some("missing launcher")
            )
            .contains("background launcher is unavailable")
        );

        let _ = fs::remove_dir_all(temp_dir);
    }

    #[test]
    fn writes_user_scoped_state_file() {
        let temp_dir = unique_temp_dir();
        let path = temp_dir.join("loopwire/state.json");

        write_state_file(&path, "{\"version\":1}\n").expect("write state file");
        let saved = fs::read_to_string(&path).expect("read state file");

        assert_eq!(saved, "{\"version\":1}\n");

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;

            let mode = fs::metadata(&path)
                .expect("state metadata")
                .permissions()
                .mode()
                & 0o777;
            assert_eq!(mode, 0o644);
        }

        let _ = fs::remove_dir_all(temp_dir);
    }

    fn unique_temp_dir() -> PathBuf {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let sequence = TEMP_DIR_COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "loopwire-startup-test-{}-{sequence}-{timestamp}",
            std::process::id()
        ));
        fs::create_dir_all(&path).expect("create temp dir");
        path
    }

    #[cfg(unix)]
    fn write_executable(path: &Path, content: &str) {
        use std::os::unix::fs::PermissionsExt;

        fs::create_dir_all(path.parent().expect("executable parent"))
            .expect("create executable parent");
        fs::write(path, content).expect("write executable");
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).expect("mark executable");
    }

    fn allows(command: &str, args: &[&str]) -> bool {
        let owned_args = args
            .iter()
            .map(|arg| (*arg).to_string())
            .collect::<Vec<_>>();
        is_allowed_audio_command(command, &owned_args)
    }
}
