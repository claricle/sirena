# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Timeline do
  include TimelineSceneHelpers

  # Expected numbers come from the mmdc references under
  # spec/fixtures_mermaid/timeline, whose viewBox starts at x=100 where the
  # scene starts at 0; 007 and 002 start 61 higher, so their y values here
  # are mmdc's plus 61 (the title).
  let(:sections) { lay_out(File.read(mmd("010"))) }
  let(:untitled) { lay_out(File.read(mmd("007"))) }
  let(:titled) { lay_out(File.read(mmd("002"))) }
  let(:linked) { lay_out(File.read(mmd("012"))) }
  let(:diagram) do
    Sirena::Parser::Timeline.new.parse("timeline\n  title T\n  2020 : A\n")
  end

  def mmd(prefix)
    Dir[File.join(__dir__, "../../mermaid/timeline", "#{prefix}*.mmd")].first
  end

  it "lays out shared pre-positioned IR identically to the private model" do
    diagram.acc_title = "Accessible history"
    ir = Sirena::Notation::Mermaid::IRAdapters::Timeline.call(diagram)
    actual = Marshal.dump(described_class.new.call(ir))

    expect(actual).to eq(Marshal.dump(described_class.new.call(diagram)))
  end

  it "sizes the canvas as mmdc does for sections" do
    expect([sections.width, sections.height]).to eq([1190, 485.6])
  end

  it "sizes the canvas as mmdc does for a title and wrapped events" do
    expect([titled.width, titled.height]).to eq([1390, 629.6])
  end

  it "keeps the viewBox in step with the size" do
    expect(titled.view_box).to eq("0 0 1390.0 629.6")
  end

  it "widens the canvas for a card text wider than its card" do
    expect(linked.width).to be_within(0.1).of(805.859)
  end

  it "places the section cards where mmdc does" do
    expect(cards_of(sections, "section").map { |card| box(card) })
      .to eq([[100, 50, 390, 67.8], [500, 50, 390, 67.8]])
  end

  it "places the period cards where mmdc does" do
    expect(cards_of(sections, "period").map { |card| box(card)[0, 2] })
      .to eq([[100, 167.8], [300, 167.8], [500, 167.8], [700, 167.8]])
  end

  it "places the events under their period" do
    expect(cards_of(untitled, "event").map { |card| box(card)[0, 2] })
      .to eq([[100, 311], [300, 311], [300, 371], [500, 311], [700, 311]])
  end

  it "drops the dashed line below the events" do
    expect(drop_line(cards_of(untitled, "period").first))
      .to eq([195, 178.8, 195, 484.4])
  end

  it "draws the base arrow across the cards" do
    axis = sections.axis

    expect([axis.x1, axis.y1, axis.x2]).to eq([50, 285.6, 1140])
  end

  it "centres the title over the cards" do
    expect([titled.title_x, titled.title_y]).to eq([245, 81])
  end

  it "keeps the card text size mmdc uses" do
    expect(cards_of(sections, "period").first.font_size).to eq(16)
  end

  it "does not send its hand-laid-out scene through Grid" do
    calls = []
    allow(Sirena::Layout::Grid).to receive(:apply) { calls << :apply }

    described_class.new.call(diagram)

    expect(calls).to be_empty
  end
end
