# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "yaml"

# Each row names an emitted diagram element, its paint attribute, the
# builtin theme key, and its category indexes (nil means a semantic role).
module RegisteredTypePaintCases
  THEMES = %i[default dark].freeze
  CASES = {
    flowchart: [
      ["//*[@id='node-A']/rect", "fill", :node_fill, [nil]],
      ["//*[@id='node-A']/rect", "stroke", :node_stroke, [nil]],
      ["//*[@id='node-A']/text", "fill", :label_text, [nil]],
    ],
    sequence: [
      ["//*[@id='participant-A']/rect", "fill", :node_fill, [nil]],
      ["//*[@id='participant-A']/rect", "stroke", :node_stroke, [nil]],
      ["//*[@id='message-0']/line", "stroke", :edge_stroke, [nil]],
    ],
    class_diagram: [
      ["//*[@id='class-A']/rect", "fill", :node_fill, [nil]],
      ["//*[@id='class-A']/rect", "stroke", :node_stroke, [nil]],
      ["//*[@id='class-A']/text", "fill", :label_text, [nil]],
    ],
    state_diagram: [
      ["//*[@id='state-A']/rect", "fill", :node_fill, [nil]],
      ["//*[@id='state-A']/rect", "stroke", :node_stroke, [nil]],
      ["//*[@id='state-A']/text", "fill", :label_text, [nil]],
    ],
    er_diagram: [
      ["//*[@id='entity-A']/rect", "fill", :node_fill, [nil]],
      ["//*[@id='entity-A']/rect", "stroke", :node_stroke, [nil]],
      ["//*[@id='entity-A']/text", "fill", :label_text, [nil]],
    ],
    user_journey: [
      ["//circle[@class='actor-0']", "fill", :user_journey_actor, [0, 0]],
      ["//rect[@class='journey-section section-type-0']", "fill",
       :user_journey_section, [0]],
      ["//rect[@class='task task-type-0']", "fill", :user_journey_section, [0]],
    ],
    gantt: [
      ["//text[.='Task1']/following-sibling::rect[1]", "fill", :primary, [nil]],
      ["//text[.='Task1']/following-sibling::rect[1]", "stroke",
       :node_stroke, [nil]],
    ],
    pie: [["//*[@id='slice-0']", "fill", :pie, [0]]],
    timeline: [
      ["//g[@class='taskWrapper']//path[@class='node-bkg']", "fill",
       :timeline_fill, [0]],
      ["//g[@class='taskWrapper']//text", "fill", :timeline_text, [0]],
      ["//g[@class='taskWrapper']//line[@class='node-line']", "stroke",
       :timeline_rule, [0]],
    ],
    quadrant: [["//g[@class='quadrant']/rect", "fill", :quadrant,
                [0, 1, 2, 3]]],
    git_graph: [
      ["//circle", "fill", :git_graph, [0]],
      ["//circle", "stroke", :git_graph, [0]],
    ],
    mindmap: [
      ["//g[@class='node mindmap-node']/circle", "stroke", :mindmap, [0]],
    ],
    kanban: [
      ["//text[.='root']/preceding-sibling::rect[1]", "fill", :primary, [nil]],
    ],
    radar: [
      ["//path[@class='radarCurve-0']", "fill", :radar, [0]],
      ["//path[@class='radarCurve-0']", "stroke", :radar, [0]],
    ],
    block: [
      ["//*[@id='block-A']/rect", "fill", :node_fill, [nil]],
      ["//*[@id='block-A']/rect", "stroke", :node_stroke, [nil]],
      ["//*[@id='block-A']/text", "fill", :label_text, [nil]],
    ],
    requirement: [
      ["//*[@id='requirement-r1']/rect[1]", "stroke", :requirement_risk, [2]],
      ["//*[@id='requirement-r1']/g/rect", "fill", :requirement_risk, [2]],
    ],
    xychart: [
      ["//rect[@stroke-width='1']", "fill", :xy, [0, 0]],
      ["//rect[@stroke-width='1']", "stroke", :xy, [0, 0]],
    ],
    architecture: [
      ["//*[@id='service-db']/rect", "fill", :node_fill, [nil]],
      ["//*[@id='service-db']/rect", "stroke", :node_stroke, [nil]],
      ["//*[@id='service-db']/text[2]", "fill", :label_text, [nil]],
    ],
    sankey: [["//path[@fill-opacity='0.4']", "fill", :flow, [0]]],
    packet: [
      ["//rect", "fill", :field_background, [nil]],
      ["//rect", "stroke", :field_border, [nil]],
      ["//text[.='Field']", "fill", :field_text, [nil]],
      ["//text[.='0']", "fill", :label_text, [nil]],
    ],
    treemap: [
      ["//text[.='Root']/preceding-sibling::rect[1]", "fill", :treemap, [0]],
    ],
    c4: [
      ["//*[@id='element-a']/rect", "fill", :primary, [nil]],
      ["//*[@id='element-a']/rect", "stroke", :edge_stroke, [nil]],
    ],
    info: [["//text[starts-with(., 'v')]", "fill", :label_text, [nil]]],
    error: [["//text[.='Error']", "fill", :error, [nil]]],
  }.freeze
end

RSpec.describe Sirena::Engine, :aggregate_failures do
  it "checks owned paint for every registered type" do
    expect(RegisteredTypePaintCases::CASES.keys).to match_array(Sirena::DiagramRegistry.types)
  end

  it "checks every named categorical palette" do
    categories = RegisteredTypePaintCases::CASES.values.flatten(1).select { |row| row[3].any? }

    expect(categories.map { |row| row[2] }.uniq)
      .to match_array(Sirena::Theme::ColorPalette::PALETTES)
  end

  RegisteredTypePaintCases::CASES.each do |type, properties|
    context "with #{type}" do
      let(:source) do
        path = SpecSupport::RepositoryPaths.path("spec/fixtures/contract/#{type}.mmd")
        File.read(path)
      end
      let(:documents) do
        RegisteredTypePaintCases::THEMES.map do |name|
          engine = described_class.new(theme: name, today: Date.new(2026, 1, 1))
          REXML::Document.new(engine.render(source))
        end
      end
      let(:colors) do
        RegisteredTypePaintCases::THEMES.map do |name|
          path = SpecSupport::RepositoryPaths.path("lib/sirena/theme/builtin/#{name}.yml")
          YAML.safe_load_file(path).fetch("colors")
        end
      end
      let(:expected_paints) do
        colors.map do |theme_colors|
          properties.map do |_selector, _attribute, key, indexes|
            indexes.map do |index|
              if index.nil?
                theme_colors.fetch(key.to_s)
              else
                theme_colors.fetch("#{key}_palette").fetch(index)
              end
            end
          end
        end
      end
      let(:actual_paints) do
        documents.map do |document|
          properties.map do |selector, attribute, _key, _indexes|
            REXML::XPath.match(document, selector).map do |element|
              element.attributes[attribute]
            end
          end
        end
      end

      it "uses exact owned paints and changes them with the theme" do
        expect(actual_paints).to eq(expected_paints)
        expect(actual_paints.last).not_to eq(actual_paints.first)
      end
    end
  end
end
