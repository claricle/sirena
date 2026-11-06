# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include DejaVuText

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

  # The JAR puts the first head 10 from the edge and the next 10 beyond it;
  # heads are as wide as their DejaVu label plus 14.
  def lifeline_centres
    first, second = %w[Participant_A Participant_B].map do |label|
      dejavu(label, size: 14) + 14.0
    end
    left = 10.0 + (first / 2)
    [left, left + ((first + second) / 2) + 10.0]
  end

  it "tracks nested activation edges" do
    right = lifeline_centres.last

    expect(timeline_end_xs(6..9)).to eq(
      [right - 7.0, right - 2.0, right + 3.0, right + 8.0],
    )
  end

  it "clears activation edges on destruction" do
    left, right = lifeline_centres

    expect(timeline_x_pairs(-2..-1)).to eq(
      [[left, right - 2.0], [right, left + 2.0]],
    )
  end
end
