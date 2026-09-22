# frozen_string_literal: true

require 'yaml'

# Rejects any external `uses:` that is not pinned to a 40-hex commit SHA, and
# any non-reusable job without `timeout-minutes`. Local `./` references are
# ours, not external.
module WorkflowPins
  SHA_REF = /\A[^@\s]+@[0-9a-f]{40}\z/

  module_function

  # Every `uses:` value in a workflow, at job level and step level.
  def uses_of(workflow)
    (workflow['jobs'] || {}).flat_map do |_, job|
      [job['uses'], *(job['steps'] || []).map { |step| step['uses'] }].compact
    end
  end

  def unpinned(workflow)
    uses_of(workflow).reject { |ref| ref.start_with?('./') || ref.match?(SHA_REF) }
  end

  # Jobs that call a reusable workflow cannot carry timeout-minutes.
  def without_timeout(workflow)
    (workflow['jobs'] || {}).reject { |_, job| job.key?('uses') || job.key?('timeout-minutes') }.keys
  end

  def problems(path)
    workflow = YAML.safe_load_file(path)
    unpinned(workflow).map { |ref| "#{path}: unpinned #{ref}" } +
      without_timeout(workflow).map { |job| "#{path}: job #{job} has no timeout-minutes" }
  end
end

if __FILE__ == $PROGRAM_NAME
  root = File.expand_path('..', __dir__)
  found = Dir[File.join(root, '.github/workflows/*.{yml,yaml}')].flat_map { |f| WorkflowPins.problems(f) }
  found.each { |line| warn line }
  puts 'workflow pins: clean' if found.empty?
  exit(found.empty? ? 0 : 1)
end
