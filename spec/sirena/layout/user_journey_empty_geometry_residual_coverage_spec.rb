# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::UserJourneyGeometry do
  it "keeps finite canvas and timeline geometry without tasks" do
    scene = JourneySceneBuilder.scene([])
    line = scene.arrows.fetch(0).line
    geometry = [
      scene.width, scene.height, scene.view_box,
      scene.tasks, scene.sections, scene.legend,
      [line.x1, line.y1, line.x2, line.y2]
    ]

    expect(geometry).to eq(
      [400.0, 45.0, "0 -25 400 20", [], [], [],
       [150.0, 200.0, 246.0, 200.0]],
    )
  end
end
