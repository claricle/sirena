#!/usr/bin/env ruby
# frozen_string_literal: true

require "elkrb"
require_relative "../lib/sirena"

module EmitAcceptSurvey
  ROOT = File.expand_path("..", __dir__)
  GRAPH_IR = %i[
    flowchart sequence class_diagram state_diagram er_diagram user_journey
    git_graph mindmap requirement architecture sankey c4
  ].freeze
  DATA_IR = %i[pie kanban radar treemap info error].freeze
  PREPOSITIONED_IR = %i[
    gantt timeline quadrant block xychart packet
  ].freeze
  DIRECT_NODE_FAILURE = %i[
    flowchart class_diagram state_diagram er_diagram mindmap block requirement
    architecture c4
  ].freeze
  HANDOFF_ACCEPTED = %i[
    flowchart sequence class_diagram state_diagram er_diagram user_journey c4
  ].freeze
  NO_HANDOFF = %i[timeline sankey].freeze

  module_function

  def run
    results = Sirena::DiagramRegistry.types.map { |type| probe(type) }
    verify(results)
    print_results(results)
  end

  def probe(type)
    handlers = Sirena::DiagramRegistry.get(type)
    diagram_ir = source_ir(type, handlers)
    layout = handlers[:transform].new
    scene = layout.call(diagram_ir)
    probe_result(type, handlers, diagram_ir, layout, scene)
  end

  def source_ir(type, handlers)
    source = File.read(example_path(type))
    diagram = handlers[:parser].new.parse(source)
    Sirena::Notation::Mermaid::IRAdapter.call(type, diagram)
  end

  def probe_result(type, handlers, diagram_ir, layout, scene)
    {
      type: type,
      transform: handlers[:transform].name,
      ir: diagram_ir.class.name.split("::").last.downcase.to_sym,
      scene: scene.class.name,
      collections: scene_collections(scene),
      direct: elkrb_result(scene),
      handoff: handoff_result(layout, diagram_ir),
    }
  end

  def example_path(type)
    paths = Dir[File.join(ROOT, "examples", type.to_s, "*.mmd")]
      .reject { |path| path.include?(".beta.") }
      .sort
    raise "no representative example for #{type}" if paths.empty?

    paths.first
  end

  def scene_collections(scene)
    scene.class.attributes.keys.filter_map do |name|
      value = scene.public_send(name)
      "#{name}=#{value.size}" if value.is_a?(Array)
    end.join(",").then { |value| value.empty? ? "none" : value }
  end

  def elkrb_result(input)
    placed = Elkrb.layout(input)
    {
      status: :accepted,
      detail: "children=#{placed.children.size},edges=#{placed.edges.size}",
    }
  rescue StandardError => e
    status = e.message.include?("ports") ? :missing_ports : :missing_children
    { status: status, detail: "#{e.class}: #{first_line(e)}" }
  end

  def handoff_result(layout, diagram_ir)
    graph = layout.send(:build_graph, diagram_ir)
    keys = graph.keys.join(",")
    result = elkrb_result(graph)
    result.merge(shape: "Hash{#{keys}}")
  rescue NotImplementedError => e
    { status: :no_handoff, shape: "none",
      detail: "#{e.class}: #{first_line(e)}" }
  end

  def first_line(error)
    error.message.lines.first.strip
  end

  def verify(results)
    expected_types = GRAPH_IR + DATA_IR + PREPOSITIONED_IR
    actual_types = results.map { |row| row[:type] }
    assert_same_members("registered types", actual_types, expected_types)
    results.each { |row| verify_row(row) }
  end

  def verify_row(row)
    type = row[:type]
    verify_ir(type, row)
    verify_scene(type, row)
    verify_status(type, "direct elkrb", row.dig(:direct, :status),
                  expected_direct_status(type))
    verify_status(type, "pre-layout elkrb", row.dig(:handoff, :status),
                  expected_handoff_status(type))
  end

  def verify_ir(type, row)
    expected_ir = ir_kind(type)
    return if row[:ir] == expected_ir

    raise "#{type}: expected #{expected_ir} IR"
  end

  def verify_scene(type, row)
    expected_scene = "#{row[:transform]}::Scene"
    return if row[:scene] == expected_scene

    raise "#{type}: expected #{expected_scene}, got #{row[:scene]}"
  end

  def verify_status(type, label, actual, expected)
    return if actual == expected

    raise "#{type}: #{label} contract changed"
  end

  def expected_direct_status(type)
    DIRECT_NODE_FAILURE.include?(type) ? :missing_ports : :missing_children
  end

  def expected_handoff_status(type)
    return :accepted if HANDOFF_ACCEPTED.include?(type)
    return :no_handoff if NO_HANDOFF.include?(type)

    :missing_children
  end

  def ir_kind(type)
    return :graph if GRAPH_IR.include?(type)
    return :data if DATA_IR.include?(type)

    :prepositioned
  end

  def assert_same_members(label, actual, expected)
    return if actual.sort == expected.sort

    raise "#{label} differ: #{actual.inspect} != #{expected.inspect}"
  end

  def print_results(results)
    puts "elkrb #{Elkrb::VERSION}; #{results.length} registered transforms"
    puts %w[
      type transform ir scene scene_collections direct_elkrb handoff
      handoff_elkrb
    ]
      .join("\t")
    results.each { |row| puts printable_row(row).join("\t") }
  end

  def printable_row(row)
    row.values_at(:type, :transform, :ir, :scene, :collections) +
      [row.dig(:direct, :detail), row.dig(:handoff, :shape),
       row.dig(:handoff, :detail)]
  end
end

EmitAcceptSurvey.run if $PROGRAM_NAME == __FILE__
