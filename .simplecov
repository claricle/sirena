# frozen_string_literal: true

# Configuration only -- SimpleCov.start is called from spec/spec_helper.rb, not
# from here (calling `.start` here is deprecated in the installed SimpleCov
# 1.2.0).
#
# Corpus results are never in a REPORT THAT SHIPS: tasks/coverage.rake's
# `--tag ~corpus` and spec/spec_helper.rb's `filter_run_excluding corpus:`
# exclude every :corpus-tagged example whenever COVERAGE=true; if either is
# bypassed, spec/spec_helper.rb's `after(:suite)` backstop fails the run
# loudly instead of shipping a corpus-inflated report. Untagged examples that
# merely read corpus fixtures are NOT covered -- tag them, don't rely on the
# fixture directory.
module SimpleCovConfiguration
  module_function

  def apply(config)
    configure_report(config)
    configure_groups(config)
    configure_floor(config)
  end

  def configure_report(config)
    config.coverage_dir ENV.fetch("SIMPLECOV_COVERAGE_DIR", "coverage")
    config.enable_coverage :branch
    # coverage/coverage.json feeds `simplecov patch`
    # (tasks/coverage.rake: coverage:changed_lines).
    config.formats :html, :json

    # `cover` includes every matching lib/ file, even when the suite never
    # requires it, so an unloaded file enters the report at 0% rather than
    # appearing to have no coverable lines. Its extension filter also keeps
    # tasks and built-in YAML themes out of the report.
    config.cover "lib/**/*.rb"
  end

  def configure_groups(config)
    # Group coverage by component so regressions remain attributable. Files
    # that match none of these paths remain in SimpleCov's Ungrouped bucket.
    config.group "Parser", %r{\Alib/sirena/parser(\.rb\z|/)}
    config.group "Diagram", %r{\Alib/sirena/diagram(\.rb\z|/)}
    config.group "Layout", %r{\Alib/sirena/layout(\.rb\z|/)}
    config.group "Renderer", %r{\Alib/sirena/renderer(\.rb\z|/)}
    config.group "Svg", %r{\Alib/sirena/svg(\.rb\z|/)}
    config.group "Theme", %r{\Alib/sirena/theme(\.rb\z|/)}
  end

  def configure_floor(config)
    # Runs with failing examples skip these line and branch floors. Coverage
    # can be order-sensitive, so re-measure several seeds before raising them.
    config.minimum_coverage line: 97.00, branch: 89.00
  end
end

SimpleCov.configure do |config|
  # A COVERAGE=true subprocess that is not spec:unit itself (e.g. a spec that
  # shells out to prove the corpus-exclusion guard -- see
  # spec/spec_helper_corpus_guard_spec.rb) would otherwise write into this
  # same directory: SimpleCov merges any .resultset.json it finds here within
  # its merge_timeout, so the child's corpus-tagged hits would land in the
  # parent's coverage.json even though the child process itself never
  # completes successfully. SIMPLECOV_COVERAGE_DIR lets such a caller point
  # the child at a throwaway directory instead, without touching the real one
  # coverage:changed_lines reads.
  # The helper keeps this configuration block below RuboCop's block-length
  # limit while leaving SimpleCov's configuration receiver explicit.
  SimpleCovConfiguration.apply(config)
end
