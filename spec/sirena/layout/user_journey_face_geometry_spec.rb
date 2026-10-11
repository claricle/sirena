# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::UserJourneyFaceGeometry do
  subject(:scene) { JourneySceneBuilder.scene(sections) }

  let(:sections) do
    [["A", [["frown", 1, []], ["flat", 3, []], ["smile", 5, []]]]]
  end
  let(:faces) { scene.tasks.map(&:face) }
  let(:svg) { Sirena::Renderer::UserJourney.new.render(scene).to_s }

  it "centres each face on its task box, lower for lower scores" do
    expect(faces.map { |face| [face.center_x, face.center_y] })
      .to eq([[225, 420], [425, 360], [625, 300]])
  end

  it "puts the eyes a third of the radius off centre and above it" do
    expect(faces.first.eyes.map { |eye| [eye.x, eye.y] })
      .to eq([[220, 415], [230, 415]])
  end

  it "publishes the frown arc in canvas coordinates" do
    expect(faces.first.mouth.path).to eq(
      "M217.5,427A7.5,7.5,0,1,1,232.5,427L231.818,427" \
      "A6.818,6.818,0,1,0,218.182,427Z",
    )
  end

  it "publishes the smile arc in canvas coordinates" do
    expect(faces.last.mouth.path).to eq(
      "M632.5,302A7.5,7.5,0,1,1,617.5,302L618.182,302" \
      "A6.818,6.818,0,1,0,631.818,302Z",
    )
  end

  it "publishes a neutral mouth as a line below the centre" do
    line = faces[1].mouth.line
    expect([line.x1, line.y1, line.x2, line.y2]).to eq([420, 367, 430, 367])
  end

  it "serializes the arcs verbatim, with no translate" do
    expect(faces.filter_map { |face| face.mouth.path })
      .to all(satisfy { |path| svg.include?(%(d="#{path}")) })
  end

  it "emits no transform anywhere in the journey" do
    expect(svg).not_to include("transform=")
  end

  it "serializes the neutral mouth line from the scene" do
    expect(svg).to include('<line class="mouth" stroke="#666" ' \
                           'stroke-width="1px" x1="420.0" y1="367.0" ' \
                           'x2="430.0" y2="367.0"/>')
  end
end
