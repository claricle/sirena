#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates the `@{ shape: ... }` name table by asking mmdc what it draws
# for every name, and keeping only the names it draws as a shape sirena
# already has.
#
# The table has to be generated rather than typed. Mermaid names about a
# hundred shapes across short names and aliases, rejects a name it does not
# know, and treats several names as the same shape — `in-out` and `lean-r`
# are one shape, not two. A hand-written table was wrong in both directions
# on its first review: it accepted three names mermaid rejects and missed
# sixty-three it renders.
#
# The mapping is measured, not curated. An earlier version of this script
# grouped names by geometry and then guessed which sirena shape each group
# meant, falling back to a rectangle whenever it could not tell. That fell
# back ninety-four times: `bang`, `cloud` and `triangle` all came out as
# plain rectangles, and five curated aliases were wrong outright — mermaid
# draws `h-cyl` lying down and `stop` with a filled centre, and neither is
# the cylinder or the double circle they were pointed at. Drawing the wrong
# shape is worse than refusing the name, so a name now earns its place only
# by matching, exactly, what mermaid draws for a shape sirena can name.
#
# Usage:
#   ruby scripts/generate_shape_table.rb candidates.txt > table.rb
#
# Needs mmdc on PATH. Slow on purpose — one browser launch per name.

require 'tmpdir'
require 'open3'
require 'digest'

# The label is the same on both sides of the comparison. Mermaid sizes a
# node around its text, and an unlabelled probe measured against a labelled
# one differs by that sizing rather than by shape.
LABEL = 'XX'

# The classic bracket syntax for each shape sirena draws. These are the
# reference drawings: mermaid renders them through the same shape code as
# the `@{ shape: ... }` names, so a name that fingerprints the same as one
# of these is that shape, and a name that matches none of them is a shape
# sirena has no way to draw.
CLASSIC = {
  'rect' => %(D["#{LABEL}"]),
  'rounded' => %(D("#{LABEL}")),
  'stadium' => %(D(["#{LABEL}"])),
  'subroutine' => %(D[["#{LABEL}"]]),
  'cylindrical' => %(D[("#{LABEL}")]),
  'circle' => %(D(("#{LABEL}"))),
  'double_circle' => %(D((("#{LABEL}")))),
  'asymmetric' => %(D>"#{LABEL}"]),
  'rhombus' => %(D{"#{LABEL}"}),
  'hexagon' => %(D{{"#{LABEL}"}}),
  'parallelogram' => %(D[/"#{LABEL}"/]),
  'parallelogram_alt' => %(D[\\"#{LABEL}"\\]),
  'trapezoid' => %(D[/"#{LABEL}"\\]),
  'trapezoid_alt' => %(D[\\"#{LABEL}"/])
}.freeze

# What mermaid draws for one diagram line, as a fingerprint of the node's
# geometry. Two bodies with the same fingerprint are the same shape.
def render(body)
  Dir.mktmpdir do |dir|
    input = File.join(dir, 'probe.mmd')
    output = File.join(dir, 'probe.svg')
    # Seeded: mermaid's rough renderer is random by default, so the same
    # shape produced a different path on every run and names were grouped
    # by noise rather than by geometry.
    File.write(input, "%%{init: {\"handDrawnSeed\": 1}}%%\n" \
                      "flowchart TD\n  #{body}\n")
    _, _, status = Open3.capture3('mmdc', '-i', input, '-o', output)
    return nil unless status.success?

    svg = File.read(output)
    # mmdc exits 0 while emitting an SVG error page, so the exit status
    # alone let a rejected shape name into the table with a fingerprint
    # taken from the error drawing.
    return nil if svg[/<svg[^>]*aria-roledescription="error"/]

    fingerprint(svg)
  end
end

# The node's own drawing, reduced to its element kinds, its path command
# letters, and its coordinates normalised into the shape's own bounding
# box. Normalising means a size difference does not read as a different
# shape, while a diamond and a parallelogram — both four-vertex paths with
# identical command letters — still differ by where their vertices sit.
def fingerprint(svg)
  node = svg[%r{<g class="nodes".*?</g></g>}m].to_s
  parts = node.scan(/<(path|polygon|rect|circle|ellipse|line)\b([^>]*)>/)
    .map { |kind, attrs| "#{kind}:#{geometry(attrs)}" }

  Digest::SHA256.hexdigest(parts.sort.join('|'))[0, 16]
end

def geometry(attrs)
  source = attrs[/\bd="([^"]*)"/, 1] || attrs[/\bpoints="([^"]*)"/, 1]

  unless source
    # Values, not just which attributes are present: ignoring them
    # collapsed a rounded rectangle into a plain one.
    return attrs.scan(/\b(rx|ry|r|width|height)="([^"]*)"/)
        .map { |k, v| "#{k}=#{v.to_f.round(2)}" }.sort.join(',')
  end

  letters = source.scan(/[A-Za-z]/).join
  "#{letters}:#{normalised(source.scan(/-?\d+(?:\.\d+)?/).map(&:to_f))}"
end

# Every other number is an x, the rest a y. Each axis is scaled into 0..1
# against its own range and rounded, so only the proportions survive.
def normalised(numbers)
  return '' if numbers.empty?

  xs = numbers.each_slice(2).map(&:first)
  ys = numbers.each_slice(2).filter_map { |pair| pair[1] }

  (scale(xs) + scale(ys)).join(',')
end

def scale(values)
  return [] if values.empty?

  low = values.min
  span = values.max - low
  return values.map { 0 } if span.zero?

  values.map { |v| ((v - low) / span * 8).round }
end

drawable = CLASSIC.to_h do |shape, body|
  warn "  drawing #{shape}"
  key = render(body)
  abort "mmdc would not draw the reference for #{shape}" unless key

  [key, shape]
end

names = ARGF.read.split(/\s+/).reject(&:empty?).uniq
accepted = {}
undrawable = []
unknown = []

names.each do |name|
  warn "  probing #{name}"
  key = render(%(D@{ shape: #{name}, label: "#{LABEL}" }))
  # Three outcomes, and the last two are different errors. mmdc would not
  # draw it at all, so mermaid does not know the name either; or mmdc drew
  # something none of the reference shapes matches, which is a shape
  # mermaid has and sirena does not.
  if key.nil?
    unknown << name
  elsif drawable[key]
    accepted[name] = drawable[key]
  else
    undrawable << name
  end
end

warn "  #{accepted.size} accepted, #{undrawable.size} undrawable, " \
     "#{unknown.size} unknown to mermaid"

puts <<~RUBY
  # frozen_string_literal: true

  # GENERATED by scripts/generate_shape_table.rb — do not edit by hand.
  #
  # The `@{ shape: ... }` names mmdc #{`mmdc --version 2>/dev/null`.strip} draws as a shape
  # sirena also draws, checked by comparing mermaid's own drawing of the
  # name against its drawing of the classic bracket syntax for that shape.
  # Names that mermaid draws identically share a mapping.
  #
  # A name is absent either because mermaid rejects it or because mermaid
  # draws something sirena has no shape for — `bang`, `cloud` and `doc` are
  # all real mermaid shapes and none of them is a rectangle. The parser
  # refuses both kinds, so an unsupported shape fails where it can be seen
  # instead of quietly coming out as a rectangle.
  #
  # Regenerate with:
  #   ruby scripts/generate_shape_table.rb scripts/probes/shape_names.txt \\
  #     > lib/sirena/parser/mermaid_shapes.rb

  module Sirena
    module Parser
      # Shape names sirena draws the way mermaid draws them.
      MERMAID_SHAPES = {
  #{accepted.sort.map { |n, s| "      #{n.inspect} => #{s.inspect}," }.join("\n")}
      }.freeze

      # Names mermaid draws and sirena has no shape for. Kept apart from the
      # names mermaid does not know at all, because the two are different
      # errors and mermaid's own message for the second one is quoted by a
      # corpus case.
      UNDRAWABLE_SHAPES = %w[
  #{undrawable.sort.each_slice(4).map { |row| "      #{row.join(' ')}" }.join("\n")}
      ].freeze

      private_constant :MERMAID_SHAPES, :UNDRAWABLE_SHAPES
    end
  end
RUBY
