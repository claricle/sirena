# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart do
  # Corpus duplicates should_handle_nested_subgraphs-b3c873b9 and
  # subgraph_spec-89dfa04b use this exact repeated-subgraph shape.
  let(:source) do
    <<~MERMAID
      graph TD
      A-->B
      subgraph myTitle
        c-->d
        subgraph inner
          e-->f
        end
        subgraph inner
          h-->i
        end
      end
    MERMAID
  end

  let(:scene) do
    diagram = Sirena::Parser::Flowchart.new.parse(source)
    described_class.new.to_graph(diagram)
  end
  let(:expected_nested_evidence) do
    [[258.0, 308.0],
     [be_within(0.5).of(35), be_within(0.5).of(35), 50.0, 50.0],
     true, 50.0,
     [be_within(0.5).of(37.5), be_within(0.5).of(37.5), 35.0, 35.0]]
  end

  def child(parent, id)
    parent.children.find { |item| item.id == id }
  end

  def margins(parent)
    horizontal_margins(parent) + vertical_margins(parent)
  end

  def horizontal_margins(parent)
    axis_margins(parent, :x, :width)
  end

  def vertical_margins(parent)
    axis_margins(parent, :y, :height)
  end

  def axis_margins(parent, axis, size)
    starts, ends = axis_extents(parent.children, axis, size)
    [starts.min - parent.public_send(axis),
     parent.public_send(axis) + parent.public_send(size) - ends.max]
  end

  def axis_extents(children, axis, size)
    children.map do |item|
      [item.public_send(axis), item.public_send(axis) + item.public_send(size)]
    end.transpose
  end

  def placement_evidence(inner, target, lower)
    inner_center = inner.x + (inner.width / 2.0)
    target_center = target.x + (target.width / 2.0)
    [inner_center == target_center, lower.y - (inner.y + inner.height)]
  end

  def nested_evidence
    outer = child(scene, "myTitle")
    inner = child(outer, "inner")
    target = child(outer, "d")
    lower = child(outer, "c")
    [[inner.width, inner.height], margins(inner),
     *placement_evidence(inner, target, lower), margins(outer)]
  end

  it "matches the nested duplicate-subgraph frame and parent placement" do
    expect(nested_evidence).to match(expected_nested_evidence)
  end
end
