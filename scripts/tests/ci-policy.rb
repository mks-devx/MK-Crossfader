#!/usr/bin/env ruby

require 'yaml'

def validate_ci(workflow)
  events = workflow.fetch('on', workflow[true]) # YAML 1.1 treats `on` as true.
  raise 'CI must only run on push and pull request.' unless events.is_a?(Hash) && events.keys.sort == %w[pull_request push]
  raise 'CI must have read-only contents permission.' unless workflow['permissions'] == { 'contents' => 'read' }

  jobs = workflow.fetch('jobs')
  raise 'The privacy job is required.' unless jobs.key?('privacy')
  jobs.each do |name, job|
    raise 'Job permissions must inherit the read-only policy.' if job.key?('permissions')
    unless name == 'privacy' || Array(job['needs']).include?('privacy')
      raise 'Build jobs must wait for the privacy check.'
    end
    job.fetch('steps').each do |step|
      if step.key?('uses') && step['uses'] != 'actions/checkout@v6'
        raise 'CI actions must be reviewed before extending the checkout-only allowlist.'
      end
      if step.fetch('run', '').match?(/Compress-Archive|upload-artifact|upload-release|gh\s+(release|api)|git\s+push/i)
        raise 'CI must not package or publish downloads.'
      end
    end
  end

  commands = jobs.fetch('vst3-windows').fetch('steps').map { |step| step['run'] }.compact
  required = [
    './vst3/tests/BuildWindowsTests.ps1',
    'cmake -S vst3 -B vst3/build-ci-windows -A x64',
    'cmake --build vst3/build-ci-windows --config Release --parallel 4',
    'ctest --test-dir vst3/build-ci-windows -C Release --output-on-failure --timeout 45'
  ]
  raise 'Windows CI must retain the reviewed build and test commands only.' unless commands == required
end

path = File.expand_path('../../.github/workflows/ci.yml', __dir__)
workflow = YAML.safe_load(File.read(path))
validate_ci(workflow)

mutations = [
  ->(data) { data['jobs']['vst3-windows']['steps'] << { 'uses' => 'actions/upload-artifact@v4' } },
  ->(data) { data['jobs']['vst3-windows']['steps'] << { 'run' => 'Compress-Archive input output.zip' } },
  ->(data) { data['jobs']['vst3-windows']['steps'] << { 'run' => 'gh release upload example output.zip' } },
  ->(data) { data['permissions']['contents'] = 'write' },
  ->(data) { data['jobs']['vst3-windows']['permissions'] = { 'contents' => 'write' } },
  ->(data) { data['jobs']['vst3-windows'].delete('needs') },
  ->(data) { data['jobs']['vst3-windows']['steps'].pop },
  ->(data) { data.fetch('on', data[true])['workflow_dispatch'] = nil }
]

mutations.each do |mutate|
  fixture = Marshal.load(Marshal.dump(workflow))
  mutate.call(fixture)
  begin
    validate_ci(fixture)
  rescue RuntimeError
    next
  end
  raise 'CI policy failed to reject an unsafe regression fixture.'
end

puts "CI publication policy passed, including #{mutations.length} rejected regression fixtures."
