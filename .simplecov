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
  # Branch coverage is measured and visible in the report (enable_coverage
  # :branch above) but deliberately carries no minimum yet -- the same
  # order-sensitivity swings it by about 0.8pp here, and the branch bar is
  # a staged timeline owned by other items besides (55->70 on item 06's PR,
  # then 07/14, then 03b's completion pass; TODO.foundation/03-coverage-gate.md,
  # "Bars"), not by this instrumentation PR.
  minimum_coverage line: 92.30
end
