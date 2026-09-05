#!/usr/bin/env ruby
# Refine each workflow's own path filter when a shared pnpm lockfile is its only matching input.
require 'json'
require 'open3'
require 'pathname'
require 'yaml'

class UncertainImpact < StandardError; end

def mapping(value, label)
  raise UncertainImpact, "#{label} must be a mapping" unless value.is_a?(Hash)

  value
end

def supported_keys(value, keys, label)
  unknown = mapping(value, label).keys - keys
  raise UncertainImpact, "unsupported #{label} fields: #{unknown.inspect}" unless unknown.empty?
end

def git_output(*args)
  output, _error, status = Open3.capture3('git', *args)
  raise UncertainImpact, "Git #{args.first} failed; required history may be missing" unless status.success?

  output
end

def commit_sha(value)
  unless value.is_a?(String) && value.match?(/\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z/i)
    raise UncertainImpact, 'event commit is not a full hexadecimal SHA'
  end
  git_output('rev-parse', '--verify', "#{value}^{commit}").strip
end

def changed_files(event_name, event)
  if event_name == 'pull_request'
    pr = mapping(event.fetch('pull_request'), 'pull request event')
    head = commit_sha(pr.fetch('head').fetch('sha'))
    base = commit_sha(pr.fetch('base').fetch('sha'))
    ancestors = git_output('merge-base', '--all', base, head).lines.map(&:strip)
    raise UncertainImpact, 'pull request has no unique merge-base' unless ancestors.length == 1

    before = commit_sha(ancestors.first)
  else
    head = commit_sha(event.fetch('after'))
    before = event.fetch('before')
    if before.is_a?(String) && before.match?(/\A(?:0{40}|0{64})\z/)
      return [git_output('ls-tree', '-r', '--name-only', '-z', head).split("\0"), nil, head]
    end
    before = commit_sha(before)
  end
  files = git_output('diff', '--name-only', '--no-renames', '-z', before, head, '--').split("\0")
  [files, before, head]
end

def path_pattern(pattern)
  # GitHub's ?, +, character classes and escapes have special semantics. Reject them rather than guess.
  unless pattern.is_a?(String) && !pattern.empty? && !pattern.match?(/[?+\[\]{}\\]/)
    raise UncertainImpact, "unsupported workflow path pattern: #{pattern.inspect}"
  end
  negative = pattern.start_with?('!')
  pattern = pattern.delete_prefix('!')
  raise UncertainImpact, 'empty or unsupported negated path pattern' if pattern.empty? || pattern.include?('!')

  expression = +''
  index = 0
  while index < pattern.length
    if pattern[index, 3] == '**/'
      expression << '(?:.*/)?'
      index += 3
    elsif pattern[index, 2] == '**'
      expression << '.*'
      index += 2
    elsif pattern[index] == '*'
      expression << '[^/]*'
      index += 1
    else
      expression << Regexp.escape(pattern[index])
      index += 1
    end
  end
  [negative, Regexp.new("\\A#{expression}\\z", Regexp::MULTILINE)]
end

def workflow_patterns(path, event_name)
  workflow = mapping(YAML.safe_load_file(path), 'workflow')
  events = mapping(workflow['on'] || workflow[true], 'workflow events')
  config = events.fetch(event_name)
  return nil if config.nil?

  mapping(config, 'workflow event configuration')
  raise UncertainImpact, 'paths-ignore filters are unsupported' if config.key?('paths-ignore')
  return nil unless config.key?('paths')

  paths = config['paths']
  raise UncertainImpact, 'workflow paths must be a nonempty list' unless paths.is_a?(Array) && !paths.empty?

  patterns = paths.map { |pattern| path_pattern(pattern) }
  raise UncertainImpact, 'workflow paths need a positive pattern' if patterns.all?(&:first)

  patterns
end

def path_matches?(path, patterns)
  patterns.reduce(false) { |matched, (negative, pattern)| pattern.match?(path) ? !negative : matched }
end

class LockProjection
  DEPENDENCIES = %w[dependencies devDependencies optionalDependencies].freeze
  GLOBALS = %w[lockfileVersion settings overrides patchedDependencies packageExtensionsChecksum catalogs
               ignoredOptionalDependencies pnpmfileChecksum].freeze
  IMPORTER_FIELDS = (DEPENDENCIES + %w[dependenciesMeta publishDirectory]).freeze
  SNAPSHOT_FIELDS = (DEPENDENCIES + %w[optional transitivePeerDependencies]).freeze
  PACKAGE_FIELDS = %w[resolution engines cpu os libc hasBin peerDependencies peerDependenciesMeta dependenciesMeta
                      bundledDependencies deprecated optional requiresBuild].freeze

  def initialize(content, surface)
    @lock = mapping(YAML.safe_load(content), 'lockfile')
    supported_keys(@lock, GLOBALS + %w[importers packages snapshots], 'lockfile')
    raise UncertainImpact, 'only pnpm lockfile version 9.0 is supported' unless @lock['lockfileVersion'].to_s == '9.0'

    @importers = mapping(@lock.fetch('importers'), 'lockfile importers')
    @packages = mapping(@lock.fetch('packages'), 'lockfile packages')
    @snapshots = mapping(@lock.fetch('snapshots'), 'lockfile snapshots')
    @selected_importers = {}
    @selected_packages = {}
    @selected_snapshots = {}
    @importer_queue = surface == 'web' ? ['.', 'apps/site', 'apps/docs'] : ['.', 'apps/desktop']
    if surface == 'application'
      @importer_queue.concat(@importers.keys.select { |key| key.is_a?(String) && key.match?(%r{\Apackages/[^/]+\z}) })
    end
    @snapshot_queue = []
  end

  def projection
    until @importer_queue.empty? && @snapshot_queue.empty?
      visit_importer(@importer_queue.shift) until @importer_queue.empty?
      visit_snapshot(@snapshot_queue.shift) until @snapshot_queue.empty?
    end
    {
      'globals' => @lock.reject { |key, _| %w[importers packages snapshots].include?(key) },
      'importers' => @selected_importers, 'packages' => @selected_packages, 'snapshots' => @selected_snapshots
    }
  end

  def visit_importer(name)
    return if @selected_importers.key?(name)

    record = mapping(@importers.fetch(name), "importer #{name}")
    supported_keys(record, IMPORTER_FIELDS, 'importer')
    @selected_importers[name] = record
    DEPENDENCIES.each do |kind|
      mapping(record.fetch(kind, {}), kind).each do |dependency, details|
        supported_keys(details, %w[specifier version], 'importer dependency')
        unless details['specifier'].is_a?(String) && details['version'].is_a?(String)
          raise UncertainImpact, 'importer dependency needs string specifier and version'
        end
        add_dependency(dependency, details.fetch('version'), importer: name)
      end
    end
  end

  def visit_snapshot(key)
    return if @selected_snapshots.key?(key)

    snapshot = mapping(@snapshots.fetch(key), "snapshot #{key}")
    supported_keys(snapshot, SNAPSHOT_FIELDS, 'snapshot')
    package_key = key.split('(', 2).first
    metadata = mapping(@packages.fetch(package_key), "package #{package_key}")
    supported_keys(metadata, PACKAGE_FIELDS, 'package metadata')
    mapping(metadata.fetch('resolution'), 'package resolution')
    @selected_snapshots[key] = snapshot
    @selected_packages[package_key] = metadata
    DEPENDENCIES.each do |kind|
      mapping(snapshot.fetch(kind, {}), kind).each { |name, reference| add_dependency(name, reference) }
    end
  end

  def add_dependency(name, reference, importer: nil)
    unless name.is_a?(String) && reference.is_a?(String)
      raise UncertainImpact, 'dependency name and reference must be strings'
    end
    if reference.start_with?('link:')
      raise UncertainImpact, 'snapshot workspace links are unsupported' unless importer

      relative = reference.delete_prefix('link:')
      raise UncertainImpact, 'absolute or empty workspace link' if relative.empty? || Pathname.new(relative).absolute?

      target = Pathname.new(File.join(importer, relative)).cleanpath.to_s
      raise UncertainImpact, 'workspace link leaves repository' if target == '..' || target.start_with?('../')

      @importer_queue << target
      return
    end
    reference = reference.delete_prefix('npm:')
    key = reference.match?(/\A\d/) ? "#{name}@#{reference}" : reference
    # Exact snapshot lookup retains peer suffixes and npm aliases; local/tarball/Git refs fail closed.
    unless key.match?(%r{\A(?:@[a-zA-Z0-9._-]+/)?[a-zA-Z0-9._-]+@\d+\.\d+\.\d+[-+a-zA-Z0-9.]*(?:\(\S+\))*\z})
      raise UncertainImpact, "unsupported dependency reference: #{reference.inspect}"
    end
    @snapshot_queue << key
  end
end

def lock_inputs_equal?(surface, before, after)
  previous = LockProjection.new(git_output('show', "#{before}:pnpm-lock.yaml"), surface).projection
  current = LockProjection.new(git_output('show', "#{after}:pnpm-lock.yaml"), surface).projection
  previous == current
end

def decide_impact(surface, workflow_path, env)
  raise UncertainImpact, 'surface must be application or web' unless %w[application web].include?(surface)

  event_name = env.fetch('GITHUB_EVENT_NAME')
  if %w[workflow_dispatch schedule].include?(event_name) ||
     (event_name == 'push' && env.fetch('GITHUB_REF', '').start_with?('refs/tags/'))
    return [true, 'manual, scheduled, or tag execution is always enabled']
  end
  raise UncertainImpact, "unsupported event: #{event_name}" unless %w[pull_request push].include?(event_name)

  patterns = workflow_patterns(workflow_path, event_name)
  return [true, 'workflow event has no path filter'] unless patterns

  event = mapping(JSON.parse(File.read(env.fetch('GITHUB_EVENT_PATH'))), 'GitHub event')
  files, before, after = changed_files(event_name, event)
  matching = files.select { |path| path_matches?(path, patterns) }
  return [false, 'no changed files match this workflow event'] if matching.empty?
  return [true, 'changed files match this workflow beyond the shared lockfile'] if matching.any? { |path| path != 'pnpm-lock.yaml' }

  raise UncertainImpact, 'initial push has no previous lockfile' unless before

  if lock_inputs_equal?(surface, before, after)
    [false, "shared lockfile changed outside the #{surface} dependency graph"]
  else
    [true, "shared lockfile changed the #{surface} dependency graph"]
  end
end

if $PROGRAM_NAME == __FILE__
  # Proof verification must reject uncertainty; workflow selection below instead runs extra checks.
  if ARGV.first == '--verify-lockfile'
    begin
      unless ARGV.length == 4 && %w[application web].include?(ARGV[1])
        raise UncertainImpact, 'usage: ruby scripts/ci-impact.rb --verify-lockfile application|web <before-sha> <after-sha>'
      end
      before, after = ARGV.drop(2).map { |value| commit_sha(value) }
      unless lock_inputs_equal?(ARGV[1], before, after)
        warn "ci-impact: #{ARGV[1]} lockfile inputs changed"
        exit 1
      end
      puts "ci-impact: #{ARGV[1]} lockfile inputs are unchanged"
      exit 0
    rescue StandardError => error
      warn "ci-impact: cannot verify lockfile inputs (#{error.message.gsub(/[\r\n]/, ' ')})"
      exit 2
    end
  end

  begin
    raise UncertainImpact, 'usage: ruby scripts/ci-impact.rb application|web <workflow.yml>' unless ARGV.length == 2

    run, reason = decide_impact(ARGV[0], ARGV[1], ENV)
  rescue StandardError => error
    run = true
    reason = "WARNING: impact is uncertain; running conservatively (#{error.message.gsub(/[\r\n]/, ' ')})"
  end
  puts "ci-impact: #{reason}"
  puts "run=#{run}"
  File.open(ENV['GITHUB_OUTPUT'], 'a') { |output| output.puts "run=#{run}" } if ENV['GITHUB_OUTPUT']
end
