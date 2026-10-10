# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe Sirena::Renderer::LineBreakText do
  let(:timeline) { "timeline\n  2000 : first<br>second\n" }
  let(:mindmap) { "mindmap\n  root\n    a<br/>b\n" }

  it "breaks a timeline label at <br>" do
    expect(Sirena::Engine.new.render(timeline)).to include(">first</tspan>")
  end

  it "starts the next timeline line in a new tspan" do
    expect(Sirena::Engine.new.render(timeline)).to include(">second</tspan>")
  end

  it "keeps no raw <br> in a timeline" do
    expect(Sirena::Engine.new.render(timeline)).not_to include("&lt;br")
  end

  it "breaks a mindmap label at <br/>" do
    expect(Sirena::Engine.new.render(mindmap)).to include(">b</tspan>")
  end

  it "keeps no raw <br/> in a mindmap" do
    expect(Sirena::Engine.new.render(mindmap)).not_to include("&lt;br")
  end

  it "leaves a label without a break as plain text" do
    svg = Sirena::Engine.new.render("mindmap\n  root\n    plain\n")
    expect(svg).not_to include("<tspan")
  end
end
