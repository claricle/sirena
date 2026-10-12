# frozen_string_literal: true

require "json"

# Turns a lane aggregator's `needs` context into a verdict. Only `success`
# is green: GitHub reports a job skipped because a prerequisite failed as
# `skipped`, and a skipped required check can let a merge through.
module LaneVerdict
  module_function

  # Returns "job: result" for every child that is not a success.
  def failures(needs, allowed_skips: [])
    return ["no child jobs to judge"] if needs.empty?

    failed = needs.reject do |name, job|
      result = job["result"]
      result == "success" ||
        (result == "skipped" && allowed_skips.include?(name))
    end
    failed.map { |name, job| "#{name}: #{job['result'].inspect}" }
  end
end

if __FILE__ == $PROGRAM_NAME
  allowed_skips = ENV.fetch("ALLOWED_SKIPS", "").split(",").reject(&:empty?)
  bad = LaneVerdict.failures(
    JSON.parse(ENV.fetch("NEEDS_JSON")), allowed_skips: allowed_skips
  )
  bad.each { |line| warn "lane red -- #{line}" }
  puts "lane green" if bad.empty?
  exit(bad.empty? ? 0 : 1)
end
