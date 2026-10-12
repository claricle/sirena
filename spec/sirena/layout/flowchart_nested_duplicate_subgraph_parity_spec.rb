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

  def child(parent, id)
    parent.children.find { |item| item.id == id }
  end

  def margins(parent)
    left = parent.children.map(&:x).min - parent.x
    right = (parent.x + parent.width) -
      parent.children.map { |item| item.x + item.width }.max
    top = parent.children.map(&:y).min - parent.y
    bottom = (parent.y + parent.height) -
      parent.children.map { |item| item.y + item.height }.max
    [left, right, top, bottom]
  end

  it "matches the nested duplicate-subgraph frame and parent placement" do
    outer = child(scene, "myTitle")
    inner = child(outer, "inner")
    target = child(outer, "d")
    lower = child(outer, "c")

    expect([inner.width, inner.height]).to eq([258.0, 308.0])
    expect(margins(inner)).to match(
      [be_within(0.5).of(35), be_within(0.5).of(35), 50.0, 50.0],
    )
    expect(inner.x + (inner.width / 2.0))
      .to eq(target.x + (target.width / 2.0))
    expect(lower.y - (inner.y + inner.height)).to eq(50.0)
    expect(margins(outer)).to match(
      [be_within(0.5).of(37.5), be_within(0.5).of(37.5), 35.0, 35.0],
    )
  end
end
