# frozen_string_literal: true

# Configuration only -- SimpleCov.start is called from spec/spec_helper.rb, not
# from here (calling `.start` here is deprecated in the installed SimpleCov
# 1.2.0).
#
# Corpus results are never in a REPORT THAT SHIPS: lib/tasks/coverage.rake's
# `--tag ~corpus` and spec/spec_helper.rb's `filter_run_excluding corpus:`
# exclude every :corpus-tagged example whenever COVERAGE=true; if either is
# bypassed, spec/spec_helper.rb's `after(:suite)` backstop fails the run
# loudly instead of shipping a corpus-inflated report. Untagged examples that
# merely read corpus fixtures are NOT covered -- tag them, don't rely on the
# fixture directory.
SimpleCov.configure do
  # A COVERAGE=true subprocess that is not spec:unit itself (e.g. a spec that
  # shells out to prove the corpus-exclusion guard -- see
  # spec/spec_helper_corpus_guard_spec.rb) would otherwise write into this
  # same directory: SimpleCov merges any .resultset.json it finds here within
  # its merge_timeout, so the child's corpus-tagged hits would land in the
  # parent's coverage.json even though the child process itself never
  # completes successfully. SIMPLECOV_COVERAGE_DIR lets such a caller point
  # the child at a throwaway directory instead, without touching the real one
  # coverage:changed_lines reads.
  coverage_dir ENV.fetch('SIMPLECOV_COVERAGE_DIR', 'coverage')

  enable_coverage :branch
  # Visible in the report (Line floor comment below) but carries no minimum
  # yet -- staged separately (TODO.foundation/03-coverage-gate.md, "Bars").

  formats :html, :json # coverage/coverage.json feeds `simplecov patch` (lib/tasks/coverage.rake: coverage:changed_lines)

  # `cover` below expands to include every lib/ file on disk matching
  # `lib/**/*.rb`, even one `spec:unit` never requires -- it enters the
  # report at 0%, not "no coverable lines" (which would count as a pass for
  # both this floor and coverage:changed_lines). The same glob is also a
  # restriction: `lib/tasks/*.rake` and `lib/sirena/theme/builtin/*.yml`
  # never appear in the report, loaded or not -- `cover` matches by
  # extension (`SimpleCov::UnloadedFileInjector.discover` /
  # `SimpleCov::Result#apply_cover_filters!`, gem source), not by whether
  # Ruby's Coverage module ever saw the file.
  cover 'lib/**/*.rb'

  # TODO.foundation/03-coverage-gate.md item 1: grouped by component, so a
  # regression is traceable to the architecture layer that caused it
  # (lib/sirena/CLAUDE.md's pipeline: Parser -> Diagram -> Transform ->
  # layout -> Renderer -> Svg). Files matched by none of these (engine.rb,
  # diagram_registry.rb, cli.rb, commands/, layout/fallback.rb,
  # text_measurement.rb, version.rb) fall into SimpleCov's own "Ungrouped"
  # bucket.
  group "Parser", %r{\Alib/sirena/parser(\.rb\z|/)}
  group "Diagram", %r{\Alib/sirena/diagram(\.rb\z|/)}
  group "Transform", %r{\Alib/sirena/transform(\.rb\z|/)}
  group "Renderer", %r{\Alib/sirena/renderer(\.rb\z|/)}
  group "Svg", %r{\Alib/sirena/svg(\.rb\z|/)}
  group "Theme", %r{\Alib/sirena/theme(\.rb\z|/)}

  # Line floor: measured baseline on `spec:unit` (`rake coverage:measure`),
  # margin below the peak. Order-sensitive -- rescue/call-site pairs in
  # renderer/{base,flowchart,pie}.rb resolve differently by execution order,
  # so re-measure across several seeds before raising this off one run. No
  # gate record on this branch has named pie.rb's exact flipping lines yet
  # (only base.rb/flowchart.rb are cited) -- pin those before citing this
  # comment as proof for pie.rb specifically. See the gate record for the
  # measurement method, the exact runs, and the version.rb/commands.rb gap
  # `cover` added.
  minimum_coverage line: 88.50
end
