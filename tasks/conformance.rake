# frozen_string_literal: true

# TODO.foundation/04, per-case conformance status in the scoreboard.
# `rake conformance` renders every spec/mermaid case and writes
# scoreboard/conformance.json; `rake conformance:check` re-runs it and fails
# when a case that was conformant is not now, or when the file is stale.

desc "Validate the spec/mermaid corpus output; writes scoreboard/conformance.json"
task :conformance do
  require_relative "support/conformance"
  puts Sirena::Conformance.record!
end

namespace :conformance do
  desc "Fail if a conformant corpus case regressed, or scoreboard/conformance.json is stale"
  task :check do
    require_relative "support/conformance"
    puts Sirena::Conformance.check!
  rescue Sirena::Conformance::RegressionError => e
    warn e.message
    abort "conformance:check: FAILED"
  end
end
