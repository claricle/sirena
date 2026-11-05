# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Drawing do
  let(:canvas) do
    Class.new { include Sirena::Notation::PlantUML::Drawing::Pen }.new
  end

  def xml
    scene = canvas.scene(50, 50)
    described_class::Renderer.new.render(scene).to_xml
  end

  it "renders an ellipse mark with its radii" do
    canvas.ellipse(10, 20, 5, 3)
    expect(xml).to include("<ellipse")
  end

  it "leaves an attribute off the element when its value is nil" do
    canvas.rect(1, 2, 3, 4, stroke: nil)
    expect(xml).not_to include("stroke=")
  end
end
