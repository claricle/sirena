# frozen_string_literal: true

require "spec_helper"

module MindmapBuilderHelpers
  def build(nodes)
    described_class.new.apply({ nodes: nodes })
  end

  def summary(result)
    result[:nodes].map do |n|
      n.values_at(:id, :content, :shape, :icon, :classes, :level)
    end
  end
end

RSpec.describe Sirena::Parser::Builders::Mindmap do
  include MindmapBuilderHelpers

  it "yields no root and no nodes for icon or class lines without a node" do
    result = build([{ icon: "fa fa-x" }, { classes: "a b" }])
    expect(result).to eq({ root: nil, nodes: [] })
  end

  it "yields an empty tree for an empty node list" do
    expect(build([])).to eq({ root: nil, nodes: [] })
  end

  it "skips non-hash entries, empty hashes and whitespace-only indents" do
    result = build([{ shape_circle: "x" }, "str", {}, { indent: " " },
                    { indent: "   ", content: "a" }])
    expect(summary(result)).to eq([["node-0", "", "circle", nil, [], 0],
                                   ["node-1", "a", "default", nil, [], 1]])
  end

  describe "icon and class lines" do
    let(:nodes) do
      [
        { indent: "", content: "root", shape_circle: "x" },
        { icon: "ic" },
        { classes: "c1  c2" },
        { indent: ["  ", " "], content: "kid", shape_bang: "!" },
        { indent: "      ", content: "g", shape_cloud: 1 },
        { indent: "    ", content: "h", shape_hexagon: 1 },
        { indent: 8, content: "z", shape_square: 1 },
      ]
    end

    let(:expected_summary) do
      [
        ["node-0", "root", "circle", "ic", %w[c1 c2], 0],
        ["node-1", "kid", "bang", nil, [], 1],
        ["node-2", "g", "cloud", nil, [], 2],
        ["node-3", "h", "hexagon", nil, [], 2],
        ["node-4", "z", "square", nil, [], 1],
      ]
    end

    it "applies them to the previous node and maps each shape",
       :aggregate_failures do
      result = build(nodes)
      expect(summary(result)).to eq(expected_summary)
      children = result[:root][:children].map { |c| c[:content] }
      expect(children).to eq(%w[kid z])
    end
  end

  it "strips embedded comment lines from an unquoted round node" do
    result = build([{ content: "r\n%% x\nok", shape_round: "(", indent: nil },
                    { indent: " ", content: "a" }])
    expect(summary(result).first[1]).to eq("r\nok")
  end

  it "drops the leading newline of an unquoted round node only" do
    unquoted = build([{ content: "\nplain", shape_round: "(" }])
    quoted = build([{ content: "\nplain", shape_round: "(",
                      round_quoted: '"' }])
    expect([unquoted[:root][:content],
            quoted[:root][:content]]).to eq(["plain", "\nplain"])
  end

  it "rejects two nodes at the same root indent" do
    expect do
      build([{ indent: "  ", content: "a" }, { indent: "  ", content: "b" }])
    end
      .to raise_error(Sirena::Parser::ParseError, "Multiple roots are illegal")
  end
end
