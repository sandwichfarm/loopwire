#!/usr/bin/env ruby
# Standard-library-only integration tests: every decision runs the public CLI in a real Git repository.
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

HELPER = File.expand_path('ci-impact.rb', __dir__)

def git(repo, *args)
  stdout, stderr, status = Open3.capture3('git', '-C', repo, *args)
  raise "git #{args.first}: #{stderr}" unless status.success?

  stdout.strip
end

def write_file(repo, name, content)
  path = File.join(repo, name)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
end

def commit(repo)
  git(repo, 'add', '--all')
  git(repo, '-c', 'user.name=CI test', '-c', 'user.email=ci@example.invalid', '-c', 'commit.gpgsign=false',
      'commit', '--quiet', '-m', 'fixture')
  git(repo, 'rev-parse', 'HEAD')
end

def fixture_lock
  importer = lambda do |dependencies|
    { 'dependencies' => dependencies.transform_values { |version| { 'specifier' => version, 'version' => version } } }
  end
  {
    'lockfileVersion' => '9.0',
    'settings' => { 'autoInstallPeers' => true, 'excludeLinksFromLockfile' => false },
    'importers' => {
      '.' => { 'devDependencies' => { 'typescript' => { 'specifier' => '6.0.3', 'version' => '6.0.3' } } },
      'apps/desktop' => importer.call('desktop' => '1.0.0(shared@1.0.0)', '@loopwire/core' => 'link:../../packages/core'),
      'apps/site' => importer.call('gsap' => '3.14.0', 'astro' => '7.0.0'),
      'apps/docs' => importer.call('vitepress' => '1.6.4'),
      'packages/core' => importer.call('core-only' => '1.0.0'),
      'packages/unlinked' => importer.call('unlinked-only' => '1.0.0')
    },
    'packages' => %w[typescript@6.0.3 desktop@1.0.0 gsap@3.14.0 astro@7.0.0 vitepress@1.6.4 shared@1.0.0
                     app-transitive@1.0.0 web-transitive@1.0.0 core-only@1.0.0 unlinked-only@1.0.0].to_h do |key|
      [key, { 'resolution' => { 'integrity' => "sha512-#{key}" } }]
    end,
    'snapshots' => {
      'typescript@6.0.3' => {},
      'desktop@1.0.0(shared@1.0.0)' => { 'dependencies' => { 'shared' => '1.0.0', 'app-transitive' => '1.0.0' } },
      'gsap@3.14.0' => {},
      'astro@7.0.0' => { 'dependencies' => { 'shared' => '1.0.0', 'web-transitive' => '1.0.0' } },
      'vitepress@1.6.4' => { 'optionalDependencies' => { 'shared' => '1.0.0' } },
      'shared@1.0.0' => {},
      'app-transitive@1.0.0' => {},
      'web-transitive@1.0.0' => {},
      'core-only@1.0.0' => {},
      'unlinked-only@1.0.0' => {}
    }
  }
end

def with_repo(paths: ['apps/desktop/**', 'packages/**', 'pnpm-lock.yaml'])
  Dir.mktmpdir('ci-impact-test-') do |repo|
    git(repo, 'init', '--quiet')
    # Keep on unquoted to exercise Ruby YAML's boolean-key interpretation.
    workflow = "on:\n  pull_request:\n    paths:\n"
    workflow += paths.map { |path| "      - #{path.to_json}\n" }.join
    workflow += "  push:\n    paths:\n"
    workflow += paths.map { |path| "      - #{path.to_json}\n" }.join
    write_file(repo, '.github/workflows/test.yml', workflow)
    write_file(repo, 'pnpm-lock.yaml', YAML.dump(fixture_lock))
    write_file(repo, 'README.md', 'base')
    write_file(repo, 'apps/desktop/old.ts', 'base')
    yield repo, commit(repo)
  end
end

def check(repo, expected, surface: 'application', event: 'push', before: nil, after: nil, ref: 'refs/heads/main', payload: nil)
  payload ||= if event == 'pull_request'
                { 'pull_request' => { 'base' => { 'sha' => before }, 'head' => { 'sha' => after } } }
              else
                { 'before' => before, 'after' => after }
              end
  event_file = File.join(repo, '.git', 'event.json')
  output_file = File.join(repo, '.git', 'action-output')
  File.write(event_file, JSON.generate(payload))
  File.write(output_file, '')
  env = { 'GITHUB_EVENT_NAME' => event, 'GITHUB_EVENT_PATH' => event_file, 'GITHUB_REF' => ref,
          'GITHUB_OUTPUT' => output_file }
  stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, HELPER, surface, '.github/workflows/test.yml', chdir: repo)
  raise "CLI failed: #{stdout} #{stderr}" unless status.success?
  raise "Expected run=#{expected}, got: #{stdout} #{stderr}" unless stdout.lines.include?("run=#{expected}\n")
  raise "Missing Actions output: #{File.read(output_file)}" unless File.read(output_file) == "run=#{expected}\n"
  raise 'Missing readable decision reason' unless stdout.lines.length >= 2

  stdout + stderr
end

def mutate_lock(repo)
  lock = YAML.safe_load_file(File.join(repo, 'pnpm-lock.yaml'))
  yield lock
  write_file(repo, 'pnpm-lock.yaml', YAML.dump(lock))
  commit(repo)
end

def test(name)
  yield
  puts "PASS #{name}"
rescue StandardError => error
  warn "FAIL #{name}: #{error.message}"
  exit 1
end

test('web-only lock update skips application and selects web') do
  with_repo do |repo, base|
    head = mutate_lock(repo) do |lock|
      lock['importers']['apps/site']['dependencies']['gsap'] = { 'specifier' => '3.15.0', 'version' => '3.15.0' }
      lock['packages']['gsap@3.15.0'] = lock['packages'].delete('gsap@3.14.0')
      lock['snapshots']['gsap@3.15.0'] = lock['snapshots'].delete('gsap@3.14.0')
    end
    check(repo, false, before: base, after: head)
    check(repo, true, surface: 'web', before: base, after: head)
  end
end

{
  'root tools' => ['typescript@6.0.3', true, true],
  'peer-qualified direct app package' => ['desktop@1.0.0', true, false],
  'app transitive integrity' => ['app-transitive@1.0.0', true, false],
  'shared transitive integrity' => ['shared@1.0.0', true, true],
  'web transitive integrity' => ['web-transitive@1.0.0', false, true],
  'workspace link dependency' => ['core-only@1.0.0', true, false],
  'unlinked packages root dependency' => ['unlinked-only@1.0.0', true, false]
}.each do |name, (package, application, web)|
  test(name) do
    with_repo do |repo, base|
      head = mutate_lock(repo) { |lock| lock['packages'][package]['resolution']['integrity'] = 'sha512-changed' }
      check(repo, application, before: base, after: head)
      check(repo, web, surface: 'web', before: base, after: head)
    end
  end
end

test('shared settings affect both surfaces') do
  with_repo do |repo, base|
    head = mutate_lock(repo) { |lock| lock['settings']['autoInstallPeers'] = false }
    %w[application web].each { |surface| check(repo, true, surface: surface, before: base, after: head) }
  end
end

test('root direct dependency upgrades affect both surfaces') do
  with_repo do |repo, base|
    head = mutate_lock(repo) do |lock|
      lock['importers']['.']['devDependencies']['typescript'] = { 'specifier' => '6.0.4', 'version' => '6.0.4' }
      lock['packages']['typescript@6.0.4'] = lock['packages'].delete('typescript@6.0.3')
      lock['snapshots']['typescript@6.0.4'] = lock['snapshots'].delete('typescript@6.0.3')
    end
    %w[application web].each { |surface| check(repo, true, surface: surface, before: base, after: head) }
  end
end

test('lockfile formatting and key order do not affect either projection') do
  with_repo do |repo, base|
    lock = YAML.safe_load_file(File.join(repo, 'pnpm-lock.yaml'))
    lock['snapshots'] = lock['snapshots'].to_a.reverse.to_h
    write_file(repo, 'pnpm-lock.yaml', "# regenerated\n#{YAML.dump(lock.to_a.reverse.to_h)}")
    head = commit(repo)
    %w[application web].each { |surface| check(repo, false, surface: surface, before: base, after: head) }
  end
end

test('selected importer metadata changes select its surface') do
  with_repo do |repo, base|
    head = mutate_lock(repo) { |lock| lock['importers']['apps/desktop']['dependencies']['desktop']['specifier'] = '^1.0.0' }
    check(repo, true, before: base, after: head)
    check(repo, false, surface: 'web', before: base, after: head)
  end
end

test('new transitive and optional dependencies are traversed') do
  with_repo do |repo, base|
    head = mutate_lock(repo) do |lock|
      lock['snapshots']['desktop@1.0.0(shared@1.0.0)']['optionalDependencies'] = { 'web-transitive' => '1.0.0' }
    end
    check(repo, true, before: base, after: head)
  end
end

test('aliases resolve by their real snapshot key') do
  with_repo do |repo, _base|
    base = mutate_lock(repo) do |lock|
      lock['importers']['apps/desktop']['dependencies']['alias'] = { 'specifier' => 'npm:shared@1.0.0', 'version' => 'shared@1.0.0' }
    end
    head = mutate_lock(repo) { |lock| lock['packages']['gsap@3.14.0']['resolution']['integrity'] = 'changed' }
    check(repo, false, before: base, after: head)
  end
end

test('scoped names and nested peer suffixes retain exact snapshots') do
  with_repo do |repo, _base|
    base = mutate_lock(repo) do |lock|
      version = '1.0.0(shared@1.0.0(@types/node@26.1.0))'
      lock['importers']['apps/desktop']['dependencies']['desktop']['version'] = version
      snapshot = lock['snapshots'].delete('desktop@1.0.0(shared@1.0.0)')
      snapshot['dependencies']['shared'] = '1.0.0(@types/node@26.1.0)'
      lock['snapshots']["desktop@#{version}"] = snapshot
      lock['snapshots']['shared@1.0.0(@types/node@26.1.0)'] = { 'dependencies' => { '@types/node' => '26.1.0' } }
      lock['snapshots']['@types/node@26.1.0'] = {}
      lock['packages']['@types/node@26.1.0'] = { 'resolution' => { 'integrity' => 'sha512-node' } }
    end
    head = mutate_lock(repo) { |lock| lock['packages']['gsap@3.14.0']['resolution']['integrity'] = 'changed' }
    check(repo, false, before: base, after: head)
    node_head = mutate_lock(repo) { |lock| lock['packages']['@types/node@26.1.0']['resolution']['integrity'] = 'changed' }
    check(repo, true, before: head, after: node_head)
  end
end

test('workspace links can bring an importer from outside the selected roots') do
  with_repo do |repo, _base|
    base = mutate_lock(repo) do |lock|
      lock['importers']['apps/desktop']['dependencies']['site'] = { 'specifier' => 'workspace:*', 'version' => 'link:../site' }
    end
    head = mutate_lock(repo) { |lock| lock['packages']['gsap@3.14.0']['resolution']['integrity'] = 'changed' }
    check(repo, true, before: base, after: head)
  end
end

{
  'future lock schema' => ->(lock) { lock['lockfileVersion'] = '10.0' },
  'missing reachable snapshot' => ->(lock) { lock['snapshots'].delete('shared@1.0.0') },
  'missing package metadata' => ->(lock) { lock['packages'].delete('shared@1.0.0') },
  'unknown snapshot metadata' => ->(lock) { lock['snapshots']['typescript@6.0.3']['futureDependencies'] = {} },
  'unknown package metadata' => ->(lock) { lock['packages']['typescript@6.0.3']['futureDependencies'] = {} },
  'unknown importer metadata' => ->(lock) { lock['importers']['.']['futureDependencies'] = {} },
  'unknown dependency metadata' => ->(lock) { lock['importers']['.']['devDependencies']['typescript']['future'] = 'x' },
  'unsupported dependency ref' => ->(lock) { lock['importers']['.']['devDependencies']['typescript']['version'] = 'file:../tool' },
  'missing required importer' => ->(lock) { lock['importers'].delete('.') }
}.each do |name, mutation|
  test("conservative fallback: #{name}") do
    with_repo do |repo, base|
      head = mutate_lock(repo, &mutation)
      output = check(repo, true, before: base, after: head)
      raise 'Missing conservative warning' unless output.include?('WARNING')
    end
  end
end

test('irrelevant changes and no changes skip') do
  with_repo do |repo, base|
    write_file(repo, 'README.md', 'updated')
    head = commit(repo)
    check(repo, false, before: base, after: head)
    check(repo, false, before: head, after: head)
  end
end

test('ordered path exclusions, reinclusion and zero-directory globstar') do
  paths = ['**', '!**/*.md', '!apps/site/**', 'apps/site/keep.md']
  with_repo(paths: paths) do |repo, base|
    write_file(repo, 'README.md', 'changed')
    head = commit(repo)
    check(repo, false, before: base, after: head)
    write_file(repo, 'apps/site/nested/new.ts', 'changed')
    next_head = commit(repo)
    check(repo, false, before: head, after: next_head)
    write_file(repo, 'apps/site/keep.md', 'changed')
    check(repo, true, before: next_head, after: commit(repo))
  end
end

test('single star does not cross directories') do
  with_repo(paths: ['apps/*/package.json']) do |repo, base|
    write_file(repo, 'apps/desktop/nested/package.json', '{}')
    head = commit(repo)
    check(repo, false, before: base, after: head)
    write_file(repo, 'apps/site/package.json', '{}')
    check(repo, true, before: head, after: commit(repo))
  end
end

test('irrelevant files alongside an unrelated lock change still skip') do
  with_repo do |repo, base|
    write_file(repo, 'README.md', 'updated')
    head = mutate_lock(repo) { |lock| lock['packages']['gsap@3.14.0']['resolution']['integrity'] = 'changed' }
    check(repo, false, before: base, after: head)
    write_file(repo, 'apps/desktop/new.ts', 'changed')
    check(repo, true, before: base, after: commit(repo))
  end
end

test('PR uses merge-base rather than changes on a moving base branch') do
  with_repo do |repo, base|
    write_file(repo, 'apps/desktop/base-only.ts', 'base branch work')
    moving_base = commit(repo)
    git(repo, 'checkout', '--quiet', '--detach', base)
    write_file(repo, 'README.md', 'PR documentation')
    head = commit(repo)
    check(repo, false, event: 'pull_request', before: moving_base, after: head)
    write_file(repo, 'apps/desktop/pr.ts', 'PR app work')
    check(repo, true, event: 'pull_request', before: moving_base, after: commit(repo))
  end
end

test('push uses the supplied before and after, not checkout HEAD') do
  with_repo do |repo, base|
    write_file(repo, 'apps/desktop/new.ts', 'app work')
    app_head = commit(repo)
    write_file(repo, 'README.md', 'docs work')
    docs_head = commit(repo)
    check(repo, true, before: base, after: app_head)
    check(repo, false, before: app_head, after: docs_head)
  end
end

test('initial pushes inspect all files at the event commit') do
  with_repo do |repo, base|
    check(repo, true, before: '0' * 40, after: base)
  end
  with_repo(paths: ['not-present/**']) do |repo, base|
    check(repo, false, before: '0' * 40, after: base)
  end
end

test('rename out of scope, deletion and newline filenames remain visible') do
  with_repo do |repo, base|
    FileUtils.mv(File.join(repo, 'apps/desktop/old.ts'), File.join(repo, 'removed-from-scope.ts'))
    renamed = commit(repo)
    check(repo, true, before: base, after: renamed)
    write_file(repo, "apps/desktop/new\nfile.ts", 'newline')
    added = commit(repo)
    check(repo, true, before: renamed, after: added)
    File.delete(File.join(repo, "apps/desktop/new\nfile.ts"))
    check(repo, true, before: added, after: commit(repo))
  end
end

test('missing Git history and invalid SHAs run conservatively') do
  with_repo do |repo, base|
    ['f' * 40, '--help', 'HEAD', "#{base}\n"].each do |before|
      output = check(repo, true, before: before, after: base)
      raise 'Missing warning' unless output.include?('WARNING')
    end
  end
end

test('missing and unsafe lockfiles run conservatively') do
  with_repo do |repo, base|
    File.delete(File.join(repo, 'pnpm-lock.yaml'))
    check(repo, true, before: base, after: commit(repo))
    write_file(repo, 'pnpm-lock.yaml', '--- !ruby/object:Object {}')
    check(repo, true, before: base, after: commit(repo))
  end
end

test('manual, scheduled, and tag events run without diff metadata') do
  with_repo do |repo, _base|
    %w[workflow_dispatch schedule].each { |event| check(repo, true, event: event, payload: {}) }
    check(repo, true, event: 'push', ref: 'refs/tags/v1.0.0', payload: {})
    check(repo, true, event: 'unknown', payload: {})
  end
end

test('unsupported workflow patterns run conservatively') do
  ['apps/[ab]/**', 'apps/file?.ts', 'apps/{site,docs}/**'].each do |pattern|
    with_repo(paths: [pattern]) do |repo, base|
      write_file(repo, 'README.md', 'changed')
      output = check(repo, true, before: base, after: commit(repo))
      raise 'Missing warning' unless output.include?('WARNING')
    end
  end
end

test('each event reads its own workflow path policy') do
  with_repo do |repo, base|
    workflow = YAML.safe_load_file(File.join(repo, '.github/workflows/test.yml'))
    workflow.fetch(true).fetch('push')['paths'] = ['README.md']
    write_file(repo, '.github/workflows/test.yml', YAML.dump(workflow))
    write_file(repo, 'README.md', 'changed')
    head = commit(repo)
    check(repo, true, before: base, after: head)
    check(repo, false, event: 'pull_request', before: base, after: head)
  end
end

puts 'ci-impact: all integration tests passed'
