# frozen_string_literal: true

require 'json'
require 'open3'

# Decides what the scoreboard guard compares against, per GitHub event.
#
#   pull_request (incl. fork) -> merge-base of the PR's base sha and HEAD
#   merge_group               -> merge-base of the queue's base sha and HEAD
#   push                      -> github.event.before
#   workflow_dispatch/schedule-> no baseline: consistency-only mode
#
# The ref is always a commit sha read from the event payload and fetched from
# the BASE repository's `origin`, never from a fork's remote.
module CiBaseline
  ZERO_SHA = '0' * 40
  CONSISTENCY = { mode: 'consistency', ref: nil, merge_base: false }.freeze

  module_function

  def resolve(event_name, payload)
    case event_name
    when 'pull_request'
      { mode: 'ref', ref: payload.dig('pull_request', 'base', 'sha'), merge_base: true }
    when 'merge_group'
      { mode: 'ref', ref: payload.dig('merge_group', 'base_sha'), merge_base: true }
    when 'push'
      before = payload['before']
      before.nil? || before == ZERO_SHA ? CONSISTENCY : { mode: 'ref', ref: before, merge_base: false }
    when 'workflow_dispatch', 'schedule'
      CONSISTENCY
    else
      raise ArgumentError, "no baseline rule for event #{event_name.inspect}"
    end
  end

  def git(*args)
    out, err, status = Open3.capture3('git', *args)
    raise "git #{args.join(' ')} failed: #{err.strip}" unless status.success?

    out.strip
  end

  # The sha to compare against, or nil in consistency mode. Fetches the ref
  # when it is not already in the clone.
  def baseline_sha(decision)
    ref = decision[:ref] or return nil
    git('fetch', '--no-tags', 'origin', ref) unless system('git', 'cat-file', '-e', "#{ref}^{commit}", err: File::NULL)
    decision[:merge_base] ? git('merge-base', ref, 'HEAD') : ref
  end
end

if __FILE__ == $PROGRAM_NAME
  event = ENV.fetch('GH_EVENT_NAME')
  payload = JSON.parse(File.read(ENV.fetch('GH_EVENT_PATH')))
  decision = CiBaseline.resolve(event, payload)
  sha = CiBaseline.baseline_sha(decision)
  lines = ["mode=#{decision[:mode]}", "sha=#{sha}"]
  puts lines
  File.open(ENV['GITHUB_OUTPUT'], 'a') { |f| f.puts(lines) } if ENV['GITHUB_OUTPUT']
end
