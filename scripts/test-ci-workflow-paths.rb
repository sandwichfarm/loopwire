#!/usr/bin/env ruby
# Exercise committed workflow policies, independently of the lockfile/Git fixture tests.
require_relative 'ci-impact'

ROOT = File.expand_path('..', __dir__)
WORKFLOWS = {
  'app' => 'ci.yml', 'aur' => 'aur.yml', 'web' => 'web.yml', 'contracts' => 'workflow-checks.yml',
  'vm' => 'vm-matrix.yml', 'deploy' => 'deploy-docs.yml'
}.freeze

parsed = WORKFLOWS.transform_values { |file| YAML.safe_load_file(File.join(ROOT, '.github/workflows', file)) }

def check(condition, message)
  raise message unless condition
end

def selected_paths(path, event, parsed)
  WORKFLOWS.filter_map do |name, file|
    events = parsed[name]['on'] || parsed[name][true]
    next unless events.key?(event)

    patterns = workflow_patterns(File.join(ROOT, '.github/workflows', file), event)
    check(patterns, "#{file} #{event} must have a path filter")
    name if path_matches?(path, patterns)
  end.sort
end

cases = {
  'apps/site/src/pages/index.astro' => [%w[web], %w[deploy web]],
  'apps/site/package.json' => [%w[web], %w[deploy web]],
  'apps/docs/docs/guide/install.md' => [%w[web], %w[deploy web]],
  'README.md' => [%w[web], %w[web]],
  'packaging/README.md' => [%w[web], %w[web]],
  '.planning/STATE.md' => [[], []],
  '.planning/quick/example/proofs/desktop.png' => [[], []],
  '.planning/REQUIREMENTS.md' => [%w[contracts], %w[contracts]],
  '.playwright-mcp/screenshot.yml' => [[], []],
  'AGENTS.md' => [[], []],
  'assets/product-screenshot.png' => [%w[web], %w[deploy web]],
  'apps/desktop/src/App.svelte' => [%w[app], %w[app aur]],
  'apps/desktop/src-tauri/Cargo.lock' => [%w[app], %w[app aur]],
  'packages/core/src/runtime.ts' => [%w[app], %w[app aur]],
  'packaging/aur/loopwire/PKGBUILD.in' => [%w[app aur], %w[app aur]],
  'packaging/aur/loopwire-git/PKGBUILD.in' => [%w[app aur], %w[app aur]],
  'packaging/aur/LICENSE-MIT' => [%w[app aur], %w[app aur]],
  'packaging/common/loopwire.desktop' => [%w[app], %w[app aur]],
  'scripts/render-aur-pkgbuild.sh' => [%w[app aur], %w[app aur]],
  'scripts/package-release.sh' => [%w[app], %w[app aur]],
  'scripts/install.sh' => [%w[app web], %w[app deploy web]],
  'scripts/deploy-docs-bunny.sh' => [%w[contracts], %w[contracts deploy]],
  'scripts/verify-docs.sh' => [%w[contracts web], %w[contracts deploy web]],
  'scripts/verify-github-workflows.sh' => [%w[contracts], %w[contracts]],
  'scripts/setup-github-actions.mjs' => [%w[contracts], %w[contracts]],
  'scripts/test-ci-workflow-paths.rb' => [%w[app aur contracts web], %w[app aur contracts web]],
  'vm/targets.tsv' => [%w[app vm web], %w[app deploy vm web]],
  'apps/docs/docs/guide/support-matrix.md' => [%w[vm web], %w[deploy vm web]],
  'apps/docs/docs/developer/vm-matrix.md' => [%w[vm web], %w[deploy vm web]],
  'package.json' => [%w[app web], %w[app aur deploy web]],
  # Lockfile entries are candidates here; the separate Git tests prove dependency-sensitive job skipping.
  'pnpm-lock.yaml' => [%w[app web], %w[app aur deploy web]],
  'pnpm-workspace.yaml' => [%w[app web], %w[app aur deploy web]],
  'tsconfig.base.json' => [%w[app web], %w[app aur deploy web]],
  '.npmrc' => [%w[app web], %w[app aur deploy web]],
  '.github/workflows/ci.yml' => [%w[app contracts], %w[app contracts]],
  '.github/workflows/aur.yml' => [%w[aur contracts], %w[aur contracts]],
  '.github/workflows/web.yml' => [%w[contracts web], %w[contracts web]],
  '.github/workflows/deploy-docs.yml' => [%w[contracts], %w[contracts deploy]],
  '.github/workflows/vm-matrix.yml' => [%w[contracts vm], %w[contracts vm]],
  '.github/workflows/release.yml' => [%w[contracts], %w[contracts]]
}
cases.each do |path, expected|
  %w[pull_request push].each_with_index do |event, index|
    actual = selected_paths(path, event, parsed)
    check(actual == expected[index].sort, "#{event} #{path}: expected #{expected[index].sort}, got #{actual}")
  end
end

{ 'app' => ['validate', 'application'], 'aur' => ['validate-aur-source', 'application'], 'web' => ['validate-web', 'web'] }.each do |name, info|
  job_id, surface = info
  workflow = parsed.fetch(name)
  jobs = workflow.fetch('jobs')
  check(!workflow.key?('concurrency'), "#{name}: an irrelevant lockfile check must not cancel an active relevant validation")
  changes = jobs.fetch('changes')
  check(changes.dig('outputs', 'run') == '${{ steps.scope.outputs.run }}', "#{name}: missing scope output")
  checkout = changes.fetch('steps').find { |step| step.fetch('uses', '').start_with?('actions/checkout@') }
  check(checkout.dig('with', 'fetch-depth') == 0, "#{name}: impact calculation needs full history")
  scope = changes.fetch('steps').find { |step| step['id'] == 'scope' }
  expected_command = "ruby scripts/ci-impact.rb #{surface} .github/workflows/#{WORKFLOWS[name]}"
  check(scope['run'] == expected_command, "#{name}: helper must read this workflow's own policy")
  job = jobs.fetch(job_id)
  check(job['needs'] == 'changes' && job['if'] == "needs.changes.outputs.run == 'true'", "#{name}: job bypasses scope output")
  check(job.dig('concurrency', 'cancel-in-progress') == true, "#{name}: preserve cancellation for actual validation jobs")
  check(workflow.dig('permissions', 'contents') == 'read', "#{name}: CI must remain read-only")
end

check(parsed['web']['jobs']['validate-web'].to_s.include?('pnpm build:web'), 'web: missing production web build')
check(parsed['web']['jobs']['validate-web'].to_s.include?('pnpm verify:requirements'), 'web: missing website requirements checks')
check(!parsed['web'].to_s.match?(/apt-get|pacman|tauri:build/), 'web: unexpected native build setup')
check(!parsed['contracts'].to_s.match?(/apt-get|pacman|tauri:build/), 'contracts: unexpected native build setup')
check(parsed['contracts'].dig('concurrency', 'cancel-in-progress') == true, 'contracts: cancel superseded validation runs')
deploy_events = parsed['deploy']['on'] || parsed['deploy'][true]
check(deploy_events.key?('workflow_dispatch') && deploy_events.dig('push', 'tags') == ['v*'], 'retain manual/release deployment')
check(parsed['deploy'].dig('concurrency', 'group') == 'deploy-docs', 'preserve serialized production deployment')
check(parsed['deploy'].dig('jobs', 'deploy-bunny', 'environment') == 'docs-production', 'preserve deployment environment')
condition = parsed['deploy'].dig('jobs', 'deploy-bunny', 'if')
check(condition == condition.strip, 'deployment condition must not become an always-true string with trailing whitespace')
%w[release final-release-proof publish-aur continuous-tests].each do |name|
  workflow = YAML.safe_load_file(File.join(ROOT, '.github/workflows', "#{name}.yml"))
  events = workflow['on'] || workflow[true]
  check(!events.key?('pull_request'), "#{name}: deliberate operator workflows must not gain PR triggers")
  check(events.key?('workflow_dispatch'), "#{name}: retain explicit operator entrypoint")
end
puts "CI workflow policy passed: #{cases.length * 2} path/event cases and selection/deployment wiring."
