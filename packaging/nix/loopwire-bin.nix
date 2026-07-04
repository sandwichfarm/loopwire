{ lib
, stdenv
, fetchurl
, makeWrapper
, nodejs
, webkitgtk_4_1
, pipewire
, wireplumber
, alsa-utils
, version
, hashes
}:

let
  artifacts = {
    x86_64-linux = {
      name = "loopwire-linux-x86_64.tar.gz";
      hash = hashes.x86_64-linux;
    };
    aarch64-linux = {
      name = "loopwire-linux-aarch64.tar.gz";
      hash = hashes.aarch64-linux;
    };
  };
  artifact = artifacts.${stdenv.hostPlatform.system} or null;
in
stdenv.mkDerivation {
  pname = "loopwire-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/sandwichfarm/loopwire/releases/download/v${version}/${artifact.name}";
    sha256 = artifact.hash;
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ nodejs webkitgtk_4_1 pipewire wireplumber alsa-utils ];

  unpackPhase = ''
    tar -xzf "$src"
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 loopwire "$out/bin/loopwire"
    install -Dm755 loopwire-dsp-provider "$out/bin/loopwire-dsp-provider"
    install -Dm755 loopwire-jack-ports "$out/bin/loopwire-jack-ports"
    mkdir -p "$out/lib/loopwire"
    cp -R libexec/loopwire/. "$out/lib/loopwire/"
    find "$out/lib/loopwire" -type d -exec chmod 0755 {} +
    find "$out/lib/loopwire" -type f -exec chmod 0644 {} +
    chmod 0755 "$out/lib/loopwire/loopwire-gui"
    wrapProgram "$out/bin/loopwire" \
      --prefix PATH : ${lib.makeBinPath [ nodejs pipewire wireplumber alsa-utils ]}
    wrapProgram "$out/bin/loopwire-dsp-provider" \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}
    wrapProgram "$out/bin/loopwire-jack-ports" \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}
    runHook postInstall
  '';

  meta = {
    description = "Linux virtual audio routing workspace";
    homepage = "https://github.com/sandwichfarm/loopwire";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "loopwire";
  };
}
