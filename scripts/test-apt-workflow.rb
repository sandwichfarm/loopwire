#!/usr/bin/env ruby
require 'yaml'

root = File.expand_path('..', __dir__)
load_workflow = ->(name) { YAML.safe_load_file(File.join(root, '.github/workflows', name)) }
check = ->(condition, message) { raise message unless condition }
apt = load_workflow.call('publish-apt.yml')
release = load_workflow.call('release.yml')
events = apt['on'] || apt[true]
check.call(!events.key?('push') && !events.key?('pull_request'), 'APT publication must not run on arbitrary pushes or PRs')
check.call(events.key?('workflow_call') && events.key?('workflow_dispatch'), 'release and operator entrypoints required')
check.call(events.fetch('schedule').any? { |schedule| schedule['cron'] == '37 5 * * 1' }, 'weekly expiry refresh required')
check.call(events.dig('workflow_dispatch', 'inputs', 'operation', 'options') == %w[publish refresh rollback], 'operator actions drifted')
check.call(apt.dig('permissions', 'contents') == 'read', 'APT publisher needs only read access to GitHub')
check.call(apt.dig('concurrency', 'cancel-in-progress') == false, 'do not interrupt an active metadata promotion')
job = apt.dig('jobs', 'publish')
check.call(job['environment'] == 'packages-production', 'production secrets must remain environment-scoped')
check.call(job['if'].include?("vars.APT_REPOSITORY_ENABLED == 'true'"), 'production must be explicitly enabled')
check.call(job['if'].include?('github.event.repository.default_branch'), 'operator publication must restrict its code ref')
check.call(job['if'] == job['if'].strip, 'job condition must not have trailing literal whitespace')
publisher = job.fetch('steps').find { |step| step['run'] == 'bash scripts/publish-apt-workflow.sh' }
check.call(publisher, 'workflow must use the reviewed publication entrypoint')
check.call(publisher.dig('env', 'OPERATION') == "${{ inputs.operation || 'refresh' }}", 'scheduled runs must refresh')
check.call(publisher.dig('env', 'RELEASE_TAG') == '${{ inputs.tag }}', 'tag input must be passed as data')
%w[APT_SIGNING_KEY APT_SSH_PRIVATE_KEY APT_SSH_KNOWN_HOSTS APT_SIGNING_PASSPHRASE].each do |name|
  check.call(publisher.dig('env', name) == "${{ secrets.#{name} }}", "#{name} must come from secrets")
end
caller = release.dig('jobs', 'publish-apt')
check.call(caller['needs'] == 'publish-release', 'APT must wait for all existing release gates')
check.call(caller['uses'] == './.github/workflows/publish-apt.yml', 'release should reuse the publication workflow')
check.call(caller.dig('with', 'tag') == '${{ needs.publish-release.outputs.tag }}', 'use the verified release tag')
publish_release = release.dig('jobs', 'publish-release')
check.call(publish_release.dig('outputs', 'tag') == '${{ steps.verified-tag.outputs.tag }}', 'release output must be verified')
check.call(publish_release.fetch('steps').last['id'] == 'verified-tag', 'tag export must follow all release evidence gates')

script = File.read(File.join(root, 'scripts/publish-apt-workflow.sh'))
publish_index = script.index('scripts/publish-package-repository.py publish')
%w[verify-release-signature.sh release-asset-manifest.mjs].each do |gate|
  check.call(script.index(gate) && script.index(gate) < publish_index, "#{gate} must precede publication")
end
check.call(script.include?('--require-checksum --require-evidence'), 'manual publication must validate release evidence inventory')
check.call(script.include?('fetch_status" -eq 3') && script.include?('operation" = publish'), 'only initial publish accepts empty origin')
check.call(script.index('python3 scripts/verify-apt-public.py') > publish_index, 'activation record requires verification of served bytes')
check.call(script.include?('--expected-revision "$expected"'), 'publication must use compare-and-swap')
check.call(script.include?('trap cleanup EXIT'), 'private signing/SSH files must be removed')
check.call(script.include?('unset APT_SSH_PRIVATE_KEY'), 'do not pass raw credentials to publisher child processes')
puts 'APT workflow contract passed: protected release ordering, explicit activation, expiry refresh, secret transport and public proof.'
