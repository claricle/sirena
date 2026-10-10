# frozen_string_literal: true

require "json"
require "open3"

# Resolves the commit a CI run compares the scoreboard against, per GitHub
# event (TODO.foundation/19 step 4). It never fetches: the workflow must have
# fetched enough history, and a missing commit raises instead of guessing.
module CiBaseline
  ZERO_SHA = "0" * 40

  Result = Struct.new(:sha, :mode, keyword_init: true) do
    def consistency_only?
      sha.nil?
    end
  end

  class Error < StandardError; end

  module_function

  # event_name: GITHUB_EVENT_NAME, payload: parsed GITHUB_EVENT_PATH JSON,
  # head: the commit under test, dir: the checkout.
  def resolve(event_name, payload, dir: ".", head: "HEAD")
    case event_name
    when "pull_request", "pull_request_target"
      pull_request(payload, dir, head)
    when "push" then push(payload, dir, head)
    when "merge_group" then merge_group(payload, dir)
    when "workflow_dispatch" then dispatch(payload, dir)
    when "schedule" then Result.new(sha: nil, mode: "schedule")
    else raise Error, "no baseline rule for event #{event_name.inspect}"
    end
  end

  def pull_request(payload, dir, head)
    base_ref = payload.dig("pull_request", "base", "ref")
    raise Error, "pull_request payload has no base.ref" if base_ref.to_s.empty?

    mode = fork?(payload) ? "fork_pull_request" : "pull_request"
    Result.new(sha: merge_base(dir, "refs/remotes/origin/#{base_ref}", head),
               mode: mode)
  end

  def fork?(payload)
    head = payload.dig("pull_request", "head", "repo", "full_name")
    base = payload.dig("pull_request", "base", "repo", "full_name")
    !head.nil? && head != base
  end

  def push(payload, dir, head)
    before = payload["before"].to_s
    if before != ZERO_SHA && commit?(dir, before)
      return Result.new(sha: rev_parse(dir, before), mode: "push")
    end

    # New branch, or a force-push that dropped `before`: use the default branch.
    default = payload.dig("repository", "default_branch")
    return Result.new(sha: nil, mode: "push_no_baseline") if default.to_s.empty?

    sha = merge_base(dir, "refs/remotes/origin/#{default}", head)
    Result.new(sha: sha, mode: "push_new_branch")
  end

  def merge_group(payload, dir)
    base = payload.dig("merge_group", "base_sha").to_s
    raise Error, "merge_group payload has no base_sha" if base.empty?
    raise Error, "merge_group base #{base} is not fetched" unless commit?(dir, base)

    Result.new(sha: rev_parse(dir, base), mode: "merge_group")
  end

  def dispatch(payload, dir)
    ref = payload.dig("inputs", "baseline_sha").to_s
    return Result.new(sha: nil, mode: "workflow_dispatch") if ref.empty?
    raise Error, "baseline_sha #{ref.inspect} is not a commit here" unless commit?(dir, ref)

    Result.new(sha: rev_parse(dir, ref), mode: "workflow_dispatch")
  end

  def merge_base(dir, ref, head)
    out, err, status = git(dir, "merge-base", ref, head)
    return out.strip if status.success?

    raise Error, "no merge-base of #{ref} and #{head} (fetch more history " \
                 "or the base ref): #{err.strip}"
  end

  def commit?(dir, ref)
    return false if ref.to_s.empty? || ref.start_with?("-")

    git(dir, "cat-file", "-e", "#{ref}^{commit}").last.success?
  end

  def rev_parse(dir, ref)
    git(dir, "rev-parse", "#{ref}^{commit}").first.strip
  end

  def git(dir, *)
    Open3.capture3("git", *, chdir: dir)
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    payload = JSON.parse(File.read(ENV.fetch("GITHUB_EVENT_PATH")))
    result = CiBaseline.resolve(ENV.fetch("GITHUB_EVENT_NAME"), payload)
    lines = ["baseline=#{result.sha}", "mode=#{result.mode}"]
    puts lines
    File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |f| f.puts(lines) } if ENV["GITHUB_OUTPUT"]
  rescue CiBaseline::Error, KeyError, Errno::ENOENT, JSON::ParserError => e
    warn "ci_baseline -- #{e.message}"
    exit 1
  end
end
