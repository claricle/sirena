# frozen_string_literal: true

# Builds the job hashes `gh run view --json jobs` emits.
module CiJobFixtures
  # +minutes+ is the job's runtime; +queued+ minutes pass before it starts.
  def ci_job(name, minutes, conclusion: "success", queued: 0)
    created = Time.utc(2026, 10, 10, 12, 0, 0)
    started = created + (queued * 60)
    { "name" => name, "conclusion" => conclusion,
      "startedAt" => started.iso8601, "completedAt" => (started + (minutes * 60)).iso8601 }
  end
end
