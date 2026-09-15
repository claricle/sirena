# frozen_string_literal: true

# Configuration only -- SimpleCov.start is called from spec/spec_helper.rb,
# not from here; calling `.start` from inside this file is deprecated in the
# installed SimpleCov (1.2.0).
#
# `spec:corpus` never requires simplecov at all (see lib/tasks/coverage.rake),
# so corpus coverage never reaches coverage.json even though this file would
# still be auto-loaded if it ever did. "Corpus results provably absent"
# (TODO.foundation/03-coverage-gate.md item 1) means every :corpus-tagged
# example is excluded whenever COVERAGE=true, via both lib/tasks/coverage.rake's
# `--tag ~corpus` AND spec/spec_helper.rb's `filter_run_excluding corpus:` --
# the latter holds regardless of which task or flag started the process. An
# example that reads corpus fixtures WITHOUT the :corpus tag is untouched by
# either exclusion and still runs inside spec:unit, instrumented like anything
# else -- the tag, not the fixture directory, is what this claim rests on.
SimpleCov.configure do
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
  # so re-measure across several seeds before raising this off one run (see
  # the gate record for the exact flipping lines and the version.rb/
  # commands.rb gap `cover` added). 92 is item 1's SECOND PR (86->92 pass).
  #
  # 88.50, not 91.60: determinism_spec.rb's full-corpus sweep is now tagged
  # :corpus (lib/tasks/coverage.rake) and excluded -- 24 measured spec:unit
  # runs (clean `coverage/` dir each time, two independent sessions of 12)
  # land at 11342-11351/12807 covered lines (88.56-88.63%), clearing this
  # floor with 7+ lines to spare at the observed low end; see the gate
  # record for the measurement method and the pre-tag number.
  minimum_coverage line: 88.50
end
