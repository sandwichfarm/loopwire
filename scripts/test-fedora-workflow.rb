#!/usr/bin/env ruby
require 'yaml'

root = File.expand_path('..', __dir__)
workflow = YAML.safe_load_file(File.join(root, '.github/workflows/publish-fedora.yml'))
release = YAML.safe_load_file(File.join(root, '.github/workflows/release.yml'))
events = workflow['on'] || workflow[true]
check = ->(condition, message) { raise message unless condition }
check.call(!events.key?('push') && !events.key?('pull_request'), 'Fedora publication must not run on arbitrary source changes')
check.call(events.key?('workflow_call') && events.key?('workflow_dispatch'), 'release and operator entrypoints required')
check.call(events.fetch('schedule').any? { |item| item['cron'] == '53 5 * * 1' }, 'weekly metadata refresh required')
check.call(events.dig('workflow_dispatch', 'inputs', 'operation', 'options') == %w[publish refresh rollback], 'operator operations drifted')
check.call(workflow.dig('permissions', 'contents') == 'read', 'GitHub access must stay read-only')
check.call(workflow.dig('concurrency', 'cancel-in-progress') == false, 'active metadata promotion must not be cancelled')
job = workflow.dig('jobs', 'publish')
check.call(job['environment'] == 'packages-production', 'production secrets must be environment-scoped')
check.call(job['if'].include?("vars.FEDORA_REPOSITORY_ENABLED == 'true'"), 'explicit repository enablement required')
check.call(job['if'].include?('github.event.repository.default_branch'), 'operator runs must use reviewed default-branch code')
check.call(job['if'] == job['if'].strip, 'job condition has literal trailing whitespace')
check.call(job.dig('container', 'image').match?(/^fedora:44@sha256:[a-f0-9]{64}$/), 'workflow must pin its Fedora toolchain')
publisher = job.fetch('steps').find { |step| step['run'] == 'bash scripts/publish-fedora-workflow.sh' }
check.call(publisher, 'workflow must use the reviewed publisher entrypoint')
check.call(publisher.dig('env', 'OPERATION') == "${{ inputs.operation || 'refresh' }}", 'scheduled runs must refresh')
%w[FEDORA_SIGNING_KEY FEDORA_SSH_PRIVATE_KEY FEDORA_SSH_KNOWN_HOSTS FEDORA_SIGNING_PASSPHRASE].each do |name|
  check.call(publisher.dig('env', name) == "${{ secrets.#{name} }}", "#{name} must come from secrets")
end
caller = release.dig('jobs', 'publish-fedora')
check.call(caller['needs'] == 'publish-release', 'Fedora publication must wait for existing release gates')
check.call(caller['uses'] == './.github/workflows/publish-fedora.yml', 'release must reuse the reviewed workflow')
check.call(caller.dig('with', 'tag') == '${{ needs.publish-release.outputs.tag }}', 'use only verified release tag output')

script = File.read(File.join(root, 'scripts/publish-fedora-workflow.sh'))
publish_index = script.index('scripts/publish-rpm-repository.py publish')
%w[verify-release-signature.sh release-asset-manifest.mjs].each do |gate|
  check.call(script.index(gate) && script.index(gate) < publish_index, "#{gate} must precede publication")
end
check.call(script.include?('--require-checksum --require-evidence'), 'public release inventory/evidence verification required')
check.call(script.include?('--expected-revision "$expected"'), 'origin publication must use revision CAS')
check.call(script.index('python3 scripts/verify-rpm-public.py') > publish_index, 'activation requires verification of served bytes')
check.call(script.include?('trap cleanup EXIT') && script.include?('unset FEDORA_SSH_PRIVATE_KEY'), 'private files/environment need cleanup')
puts 'Fedora workflow contract passed: pinned toolchain, protected release ordering, secret transport, refresh and public proof.'
