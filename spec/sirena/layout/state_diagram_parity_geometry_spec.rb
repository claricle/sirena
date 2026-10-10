# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  subject(:scene) do
    diagram = Sirena::Parser::StateDiagram.new.parse(<<~MERMAID)
      stateDiagram-v2
      [*] --> Still
      Still --> [*]
    MERMAID
    described_class.new.to_graph(diagram)
  end

  def terminal?(node)
    case node.shape_type
    when "start", "end" then true
    else false
    end
  end

  def terminal_geometry
    scene.children.select { |node| terminal?(node) }.map do |node|
      [node.shape_type, node.width, node.height, node.radius,
       node.inner_radius]
    end
  end

  it "renders Mermaid-sized terminals inside stable layout boxes" do
    expect(terminal_geometry).to contain_exactly(
      ["start", 30.0, 30.0, 7.0, 2.0],
      ["end", 30.0, 30.0, 7.0, 2.0],
    )
  end

  it "orients default-grid terminals down the page" do
    nodes = scene.children.to_h { |node| [node.shape_type, node] }

    expect(nodes.fetch("start").center_y)
      .to be < nodes.fetch("end").center_y
  end
end
