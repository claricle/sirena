# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:source) do
    path = Dir[File.expand_path(
      "../../../../plantuml/sequence/" \
      "java.nonreg.simple.TeozTimelineIssues_0003_Test--*.puml",
      __dir__,
    )].fetch(0)
    File.read(path)
  end

  let(:scene) do
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    parsed.transform.new.call(parsed.diagram)
  end

  def x_points(arrow)
    arrow.path.scan(/[ML] (\S+) \S+/).map { |x| x.first.to_f }
  end

  it "reserves activation interior and lands messages on exposed bar edges" do
    lifelines = scene.lifelines.map(&:x1)
    first_bar_edges = [scene.bars[0].x + scene.bars[0].width,
                       scene.bars[1].x - 2.0]

    expect([lifelines.last - lifelines.first, x_points(scene.arrows.first)])
      .to eq([68.03173828125, first_bar_edges])
  end
end
