#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates the `@{ shape: ... }` name table by asking mmdc, one name at a
# time, and grouping the ones that render identically.
#
# The table has to be generated rather than typed. Mermaid names about a
# hundred shapes across short names and aliases, rejects a name it does not
# know, and treats several names as the same shape — `in-out` and `lean-r`
# are one shape, not two. A hand-written table was wrong in both directions
# on its first review: it accepted three names mermaid rejects and missed
# sixty-three it renders.
#
# Usage:
#   ruby scripts/generate_shape_table.rb candidates.txt > table.yml
#
# Needs mmdc on PATH. Slow on purpose — one browser launch per name.

require 'tmpdir'
require 'open3'
require 'digest'
require 'yaml'

# What mermaid draws for a name, as a fingerprint of the node's geometry.
# Two names with the same fingerprint are the same shape.
def render(name)
  Dir.mktmpdir do |dir|
    input = File.join(dir, 'probe.mmd')
    output = File.join(dir, 'probe.svg')
    # Seeded: mermaid's rough renderer is random by default, so the same
    # shape produced a different path on every run and names were grouped
    # by noise rather than by geometry.
    File.write(input, "%%{init: {\"handDrawnSeed\": 1}}%%\n" \
                      "flowchart TD\n  D@{ shape: #{name} }\n")
    _, _, status = Open3.capture3('mmdc', '-i', input, '-o', output)
    return nil unless status.success?

    fingerprint(File.read(output))
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

names = ARGF.read.split(/\s+/).reject(&:empty?).uniq
accepted = {}
rejected = []

names.each do |name|
  warn "  probing #{name}"
  key = render(name)
  key ? (accepted[name] = key) : rejected << name
end

groups = accepted.group_by { |_, key| key }
  .transform_values { |pairs| pairs.map(&:first).sort }

warn "  #{accepted.size} accepted, #{rejected.size} rejected, " \
     "#{groups.size} distinct shapes"
warn "  rejected: #{rejected.sort.join(' ')}" unless rejected.empty?

# Which names mermaid ACCEPTS is generated and exact — that is the part
# that must not drift, because mermaid rejects a name it does not know and
# so must we.
#
# Which sirena shape each one maps to is a judgement call, and is curated
# below. Sirena names fourteen shapes and draws five, so most names land on
# a rectangle either way; the table exists so the close matches are right,
# not so every name is distinct.
SIRENA_SHAPES = %w[
  double_circle circle stadium subroutine cylindrical rhombus hexagon
  parallelogram_alt parallelogram trapezoid_alt trapezoid asymmetric
  rounded rect
].freeze

ALIASES = {
  'dbl-circ' => 'double_circle', 'double-circle' => 'double_circle',
  'framed-circle' => 'double_circle', 'fr-circ' => 'double_circle',
  'filled-circle' => 'double_circle', 'junction' => 'double_circle',
  'stop' => 'double_circle',
  'circ' => 'circle', 'sm-circ' => 'circle', 'small-circle' => 'circle',
  'start' => 'circle',
  'cyl' => 'cylindrical', 'db' => 'cylindrical', 'database' => 'cylindrical',
  'cylinder' => 'cylindrical', 'disk' => 'cylindrical',
  'lin-cyl' => 'cylindrical', 'lined-cylinder' => 'cylindrical',
  'h-cyl' => 'cylindrical', 'horizontal-cylinder' => 'cylindrical',
  'das' => 'cylindrical',
  'diam' => 'rhombus', 'diamond' => 'rhombus', 'decision' => 'rhombus',
  'question' => 'rhombus',
  'hex' => 'hexagon', 'hexagon' => 'hexagon', 'prepare' => 'hexagon',
  'lean-r' => 'parallelogram', 'lean-right' => 'parallelogram',
  'in-out' => 'parallelogram',
  'lean-l' => 'parallelogram_alt', 'lean-left' => 'parallelogram_alt',
  'out-in' => 'parallelogram_alt',
  'trap-b' => 'trapezoid', 'trapezoid-bottom' => 'trapezoid',
  'priority' => 'trapezoid', 'trapezoid' => 'trapezoid',
  'trap-t' => 'trapezoid_alt', 'trapezoid-top' => 'trapezoid_alt',
  'manual' => 'trapezoid_alt', 'inv-trapezoid' => 'trapezoid_alt',
  'pill' => 'stadium', 'terminal' => 'stadium', 'stadium' => 'stadium',
  'subprocess' => 'subroutine', 'subroutine' => 'subroutine',
  'fr-rect' => 'subroutine', 'framed-rectangle' => 'subroutine',
  'rounded' => 'rounded', 'event' => 'rounded',
  'odd' => 'asymmetric'
}.freeze

def sirena_shape(group)
  named = group.filter_map { |name| ALIASES[name] }.first
  return named if named

  SIRENA_SHAPES.find { |shape| group.include?(shape) } || 'rect'
end

entries = groups.values.sort_by(&:first).flat_map do |group|
  shape = sirena_shape(group)
  group.sort.map { |name| [name, shape] }
end.sort

puts <<~RUBY
  # frozen_string_literal: true

  # GENERATED by scripts/generate_shape_table.rb — do not edit by hand.
  #
  # Every `@{ shape: ... }` name mmdc #{`mmdc --version 2>/dev/null`.strip} accepts, mapped onto
  # the shapes sirena can name. Names that mermaid draws identically share
  # a mapping; names mermaid rejects are absent, and the parser raises on
  # them because mermaid does too.
  #
  # Regenerate with:
  #   ruby scripts/generate_shape_table.rb scripts/probes/shape_names.txt \\
  #     > lib/sirena/parser/mermaid_shapes.rb

  module Sirena
    module Parser
      # Shape names mermaid accepts, and what sirena draws for each.
      MERMAID_SHAPES = {
  #{entries.map { |n, s| "      #{n.inspect} => #{s.inspect}," }.join("\n")}
      }.freeze
    end
  end
RUBY
