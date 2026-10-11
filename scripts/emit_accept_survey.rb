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
    diagram = handlers[:parser].new.parse(File.read(example_path(type)))
    ir = Sirena::Notation::Mermaid::IRAdapter.call(type, diagram)
    layout = handlers[:transform].new
    scene = layout.call(ir)
    {
      type: type,
      transform: handlers[:transform].name,
      ir: ir.class.name.split("::").last.downcase.to_sym,
      scene: scene.class.name,
      collections: scene_collections(scene),
      direct: elkrb_result(scene),
      handoff: handoff_result(layout, ir),
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

  def handoff_result(layout, ir)
    graph = layout.send(:build_graph, ir)
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
    expected_ir = ir_kind(type)
    raise "#{type}: expected #{expected_ir} IR" unless row[:ir] == expected_ir

    expected_scene = "#{row[:transform]}::Scene"
    unless row[:scene] == expected_scene
      raise "#{type}: expected #{expected_scene}, got #{row[:scene]}"
    end

    expected_direct = if DIRECT_NODE_FAILURE.include?(type)
                        :missing_ports
                      else
                        :missing_children
                      end
    unless row.dig(:direct, :status) == expected_direct
      raise "#{type}: direct elkrb contract changed"
    end

    expected_handoff = if HANDOFF_ACCEPTED.include?(type)
                         :accepted
                       elsif NO_HANDOFF.include?(type)
                         :no_handoff
                       else
                         :missing_children
                       end
    return if row.dig(:handoff, :status) == expected_handoff

    raise "#{type}: pre-layout elkrb contract changed"
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
    results.each do |row|
      puts [
        row[:type], row[:transform], row[:ir], row[:scene],
        row[:collections], row.dig(:direct, :detail),
        row.dig(:handoff, :shape), row.dig(:handoff, :detail)
      ].join("\t")
    end
  end
end

EmitAcceptSurvey.run if $PROGRAM_NAME == __FILE__
