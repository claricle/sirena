# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  let(:xml) do
    Sirena.render("sequenceDiagram\nactor D as dee\nparticipant A\nD->>A: hi\n")
  end
  let(:group) { xml[%r{<g id="participant-D".*?</g>}m] }
  let(:label_y) { group[/<text[^>]* y="([\d.]+)"/, 1].to_f }
  let(:leg_ys) { group.scan(/y2="([\d.]+)"/).flatten.map(&:to_f) }

  it "draws the alias under the stick figure" do
    expect(group).to include(">dee</text>")
  end

  it "puts the alias below the figure's feet" do
    expect(label_y).to be > leg_ys.max
  end

  it "draws a plain participant label once" do
    expect(xml.scan(">A</text>").length).to eq(1)
  end
end
