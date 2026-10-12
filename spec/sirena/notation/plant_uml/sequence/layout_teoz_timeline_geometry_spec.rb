# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:root) { File.expand_path("../../../../plantuml/sequence", __dir__) }
  let(:notes_case) do
    "java.nonreg.simple.TeozTimelineIssues_0002_Test--c35d69988621"
  end
  let(:timeline_case) do
    "resources.vega.asciiverse.timeline_002--f985a9b8f0de"
  end
  let(:timeline) { scene_for(timeline_case) }

  def scene_for(case_id, source: nil)
    source ||= File.read(File.join(root, "#{case_id}.puml"))
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    parsed.transform.new.call(parsed.diagram)
  end

  def arrow_points(arrow)
    arrow.path.scan(/[ML] (\S+) (\S+)/).map do |x, y|
      [x.to_f, y.to_f]
    end
  end

  def lifeline_xs(scene)
    scene.lifelines.map(&:x1)
  end

  def timeline_start_ys
    timeline.arrows.map { |arrow| arrow_points(arrow).first.last }
  end

  def timeline_end_xs(range)
    timeline.arrows[range].map { |arrow| arrow_points(arrow).last.first }
  end

  def timeline_x_pairs(range)
    timeline.arrows[range].map { |arrow| arrow_points(arrow).map(&:first) }
  end

  it "does not widen Teoz lifeline gaps for attached parallel notes" do
    source = File.read(File.join(root, "#{notes_case}.puml"))
    with_notes = scene_for(notes_case, source: source)
    stripped = source.gsub(/^note right.*\n/, "")
    without_notes = scene_for(notes_case, source: stripped)

    expect(lifeline_xs(with_notes)).to eq(lifeline_xs(without_notes))
  end

  it "uses the pinned cadence for unlabelled Teoz group timelines" do
    expect(timeline_start_ys.values_at(0, 1, 2, 27, 28).map(&:round)).to eq(
      [87, 101, 160, 782, 796],
    )
  end

  it "tracks nested activation edges" do
    expect(timeline_end_xs(6..9)).to eq(
      [168.43603515625, 173.43603515625, 178.43603515625, 183.43603515625],
    )
  end

  it "clears activation edges on destruction" do
    expect(timeline_x_pairs(-2..-1)).to eq(
      [[61.4130859375, 173.43603515625],
       [173.43603515625, 61.4130859375]],
    )
  end
end
