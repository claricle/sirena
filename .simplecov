# frozen_string_literal: true

# Configuration only -- SimpleCov.start is called from spec/spec_helper.rb,
# not from here. `require "simplecov"` auto-loads this file by walking up
# from the process's working directory looking for `.simplecov`; calling
# `.start` from inside it is deprecated in the installed SimpleCov (1.2.0).
#
# This file is loaded by ANY process that `require "simplecov"`, including
# `spec:corpus` if it ever opts in by accident -- but `spec:corpus` never
# requires simplecov at all (see Rakefile), so its coverage never reaches
# .resultset.json / coverage.json and can never inflate the numbers below.
# TODO.foundation/03-coverage-gate.md item 1 ("corpus results provably
# absent from the coverage number") is enforced by that omission, not by a
# filter in this file -- there is nothing here for a filter to exclude.
SimpleCov.configure do
  enable_coverage :branch

  formats :html, :json # coverage/coverage.json feeds `simplecov patch` (Rakefile: coverage:changed_lines)

  # Every lib/ file on disk enters the report at 0% even if the suite never
  # requires it. Without this, a file `spec:unit` never loads carries no
  # coverage.json entry at all, and both the global floor and
  # coverage:changed_lines score it as "no coverable lines" -- a pass, not a
  # gap. `cover` also restricts the report to this glob; lib/ does hold
  # non-.rb files (lib/tasks/*.rake, lib/sirena/theme/builtin/*.yml --
  # confirmed via `find lib -type f ! -name "*.rb"`), but none of them drop
  # out of scope because of this glob: Ruby's Coverage module (which
  # SimpleCov reads) only ever tracks files loaded as Ruby source via
  # `require`/`load` IN THE INSTRUMENTED PROCESS. The Rakefile's own
  # `Dir.glob('lib/tasks/**/*.rake').each { |r| load r }` does load the
  # .rake files -- but into the parent `rake` process, before
  # `coverage:measure` ever runs; `RSpec::Core::RakeTask` then spawns
  # `spec:unit` via `system(...)`, a genuinely separate OS process whose own
  # Coverage instrumentation starts fresh and never sees what the parent
  # loaded. The .yml files are never `require`d/`load`ed at all (read via
  # `File.read` in `Sirena::Theme.load`, `lib/sirena/theme.rb`). Confirmed
  # empirically, not just reasoned: this
  # session's `coverage/coverage.json` (188 files) has zero entries ending
  # in `.rake` or `.yml`.
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

  # Line floor: today's measured baseline on `spec:unit` (`rake
  # coverage:measure`), with a deliberate margin below the peak -- line
  # coverage here is order-sensitive (lib/sirena/renderer/base.rb:119's
  # rescue and its two call sites in renderer/flowchart.rb:126,404 resolve
  # differently depending on example execution order), so do not raise this
  # floor off a single run; re-measure across several seeds first, or it
  # will flake. TODO.foundation/03-coverage-gate.md's 92 floor is this
  # item's SECOND PR (the 86->92 test pass), not this one.
  #
  # The `cover 'lib/**/*.rb'` line above added lib/sirena/version.rb (loaded
  # once by the gemspec before SimpleCov.start ever runs, so Ruby's
  # single-execution `require` leaves it looking untouched here even though
  # it ran) and lib/sirena/commands/{batch,render}.rb (genuinely exercised by
  # no example) to what this floor is measured against, which is why it
  # reads lower than the 92.30 an incomplete report gave. Closing either gap
  # for real is out of scope here -- that belongs with the 86->92 test pass.
  #
  # Branch coverage is measured and visible in the report (enable_coverage
  # :branch above) but deliberately carries no minimum yet -- the same
  # order-sensitivity swings it by about 0.8pp here, and the branch bar is
  # a staged timeline owned by other items besides (55->70 on item 06's PR,
  # then 07/14, then 03b's completion pass; TODO.foundation/03-coverage-gate.md,
  # "Bars"), not by this instrumentation PR.
  minimum_coverage line: 91.60
end
