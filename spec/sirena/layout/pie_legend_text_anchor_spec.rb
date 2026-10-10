# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::PieLegend do
  let(:scene) do
    diagram = Sirena::Diagram::Pie.new
    diagram.slices = [Sirena::Diagram::PieSlice.new(label: "Bandy", value: 40),
                      Sirena::Diagram::PieSlice.new(label: "Hockey", value: 80)]
    Sirena::Layout::Pie.new.to_graph(diagram)
  end
  let(:caption_tags) do
    ->(entry) { svg.scan(/<text [^>]*>#{entry.text}<\/text>/) }
  end
  let(:svg) { Sirena::Renderer::Pie.new.render(scene).to_s }

  it "text anchor: sits right of the swatch in the Scene" do
    expect(scene.legend.map { |e| [e.text_x - e.x, e.text_y - e.y] })
      .to all(eq([22.0, 14.0]))
  end

  it "renders each caption at the Scene's anchor" do
    scene.legend.each do |entry|
      expect(caption_tags.call(entry).first)
        .to include(%(x="#{entry.text_x}"), %(y="#{entry.text_y}"))
    end
  end

  it "renders a moved anchor, so the renderer adds nothing of its own" do
    scene.legend.first.text_x = 1000.0
    scene.legend.first.text_y = 2000.0
    expect(caption_tags.call(scene.legend.first).first)
      .to include('x="1000.0"', 'y="2000.0"')
  end
end
