# frozen_string_literal: true

require "json"
require "time"

# Times the two CI lanes from `gh run view --json jobs` output.
#
# A lane's time in one run is its slowest job, started_at to completed_at, so
# runner queue time is excluded. Runs are then split by the cache state the
# slowest job's ruby/setup-ruby step logged.
module CiLaneTimings
  LANES = {
    "fast" => /\A(?:unit \(|pins\z|oracle-toolchain\z|lint\z)/,
    "full" => %r{\A(?:docs-build /|links /|conformance\z|fresh-resolution\z|plantuml-toolchain\z)},
  }.freeze

  BUCKETS = %i[warm restore_key cold none].freeze

  module_function

  # Jobs that belong to +lane+ and actually ran (a skipped job has no runtime).
  def lane_jobs(jobs, lane)
    jobs.select do |job|
      job["name"].match?(LANES.fetch(lane)) &&
        job["conclusion"] != "skipped" &&
        job["startedAt"] && job["completedAt"]
    end
  end

  def duration(job)
    Time.iso8601(job["completedAt"]) - Time.iso8601(job["startedAt"])
  end

  def slowest(jobs, lane)
    lane_jobs(jobs, lane).max_by { |job| duration(job) }
  end

  # Cache state from a job log: :warm (exact key hit), :restore_key (partial
  # hit), :cold (a key was computed and nothing restored), or nil (no cache
  # line at all, e.g. a job with bundler-cache off).
  def classify_log(text)
    if text.include?("Cache hit for:") then :warm
    elsif text.include?("Cache hit for restore-key:") then :restore_key
    elsif text.include?("Cache key:") then :cold
    end
  end

  # +caches+ maps job name => classification for the jobs whose logs were read.
  # Returns nil when the lane has no job that ran.
  def sample(jobs, lane, caches)
    job = slowest(jobs, lane) or return nil
    { job: job["name"], seconds: duration(job), cache: caches[job["name"]] || :none }
  end

  def median(values)
    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  # +samples+ is an array of #sample results. Minutes, per cache bucket.
  def summarize(samples)
    BUCKETS.to_h do |bucket|
      minutes = samples.select { |s| s[:cache] == bucket }.map { |s| s[:seconds] / 60.0 }
      [bucket, { count: minutes.size, median: minutes.empty? ? nil : median(minutes), max: minutes.max }]
    end
  end
end

# Fetching lives here so the module above stays pure. Read-only gh calls.
if __FILE__ == $PROGRAM_NAME
  require "open3"
  repo, since, limit = ARGV
  abort "usage: ci_lane_timings.rb OWNER/REPO SINCE_ISO8601 [LIMIT]" unless repo && since

  gh = lambda do |*args|
    out, err, status = Open3.capture3("gh", *args)
    status.success? ? out : (warn(err) || nil)
  end

  runs = JSON.parse(gh.call("run", "list", "-R", repo, "--workflow", "ci", "--status", "success",
                            "--limit", "200", "--json", "databaseId,createdAt,headBranch,event"))
  runs = runs.select { |r| Time.iso8601(r["createdAt"]) >= Time.iso8601(since) }
  runs = runs.first(Integer(limit || 60))

  samples = { "fast" => [], "full" => [] }
  runs.each do |run|
    jobs = JSON.parse(gh.call("run", "view", run["databaseId"].to_s, "-R", repo, "--json", "jobs"))["jobs"]
    next unless jobs.any? { |j| j["name"].include?("windows-latest, shard") } # sharded topology only

    caches = {}
    CiLaneTimings::LANES.each_key do |lane|
      job = CiLaneTimings.slowest(jobs, lane) or next
      log = gh.call("api", "repos/#{repo}/actions/jobs/#{job['databaseId']}/logs").to_s
      caches[job["name"]] = CiLaneTimings.classify_log(log)
      s = CiLaneTimings.sample(jobs, lane, caches)
      samples[lane] << s
      puts [run["databaseId"], lane, s[:job], s[:seconds].round, s[:cache]].join("\t")
    end
  end
  samples.each do |lane, list|
    puts "#{lane}: #{list.size} runs"
    CiLaneTimings.summarize(list).each do |bucket, v|
      puts "  #{bucket.to_s.ljust(12)} n=#{v[:count]} " \
           "median=#{v[:median]&.round(1)} max=#{v[:max]&.round(1)}"
    end
  end
end
