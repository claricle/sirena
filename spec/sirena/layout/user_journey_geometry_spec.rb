# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::UserJourneyGeometry do
  subject(:scene) { JourneySceneBuilder.scene(sections, title: title) }

  let(:title) { nil }
  let(:sections) do
    [["A", [["a1", 5, %w[Zed Amy]], ["a2", 1, %w[Amy]]]],
     ["Empty", []],
     ["B", [["b1", 3, []]]]]
  end

  it "gives a run of tasks one band as wide as the run, less 50" do
    expect(scene.sections.map { |band| band.box.width }).to eq([350, 150])
  end

  it "puts every band at y=50, 50px high" do
    expect(scene.sections.map { |band| [band.box.y, band.box.height] })
      .to eq([[50, 50], [50, 50]])
  end

  it "starts a band over its first task column" do
    expect(scene.sections.map { |band| band.box.x }).to eq([150, 550])
  end

  it "draws no band for a section without tasks" do
    expect(scene.sections.length).to eq(2)
  end

  it "skips the empty section when numbering band colours" do
    expect(scene.sections.map(&:number)).to eq([0, 1])
  end

  it "fills bands in the mmdc section palette" do
    expect(scene.sections.map { |band| band.box.fill })
      .to eq(%w[#191970 #8B008B])
  end

  it "centres a band label on the band" do
    expect(scene.sections.first.labels.map { |l| [l.x, l.y] })
      .to eq([[325.0, 75.0]])
  end

  it "hangs task boxes at y=110, 150 wide and 50 high" do
    expect(scene.tasks.map { |t| [t.box.y, t.box.width, t.box.height] })
      .to all(eq([110, 150, 50]))
  end

  it "ends every task line at y=450" do
    expect(scene.tasks.map(&:line_end)).to all(eq(450))
  end

  it "colours tasks like their section" do
    expect(scene.tasks.map { |task| task.box.fill })
      .to eq(%w[#191970 #191970 #8B008B])
  end

  it "spaces a task's actor dots 10px apart from 14px in" do
    expect(scene.tasks.first.dots.map(&:x)).to eq([164, 174])
  end

  it "puts actor dots on the task row" do
    expect(scene.tasks.first.dots.map(&:y)).to all(eq(110))
  end

  it "numbers dots by the alphabetical legend" do
    expect(scene.tasks.first.dots.map(&:index)).to eq([1, 0])
  end

  it "stacks legend dots at x=20 from y=60" do
    expect(scene.legend.map { |actor| [actor.dot.x, actor.dot.y] })
      .to eq([[20, 60], [20, 80]])
  end

  it "sets the scene width to margin + last column + 100 + margin" do
    expect(scene.width).to eq(900)
  end

  it "ends the viewBox at the task lines plus 20" do
    expect(scene.view_box).to eq("0 -25 900 470")
  end

  context "with a title" do
    let(:title) { "Trip" }

    it "adds 70 to the viewBox height" do
      expect(scene.view_box).to eq("0 -25 900 540")
    end

    it "sets the title at the left margin, y=25" do
      expect([scene.title.x, scene.title.y]).to eq([150, 25])
    end
  end

  context "when tasks come before any section" do
    subject(:scene) { JourneySceneBuilder.unsectioned }

    it "fills their box grey" do
      expect(scene.tasks.first.box.fill).to eq("#CCC")
    end

    it "draws no band for them" do
      expect(scene.sections).to be_empty
    end
  end

  context "with more sections than palette colours" do
    let(:sections) { Array.new(8) { |i| ["S#{i}", [["t", 3, []]]] } }

    it "starts the palette over" do
      expect(scene.sections.last.box.fill).to eq("#191970")
    end

    it "starts the section type numbers over" do
      expect(scene.sections.map(&:number)).to eq([0, 1, 2, 3, 4, 5, 6, 0])
    end
  end

  context "with more actors than dot colours" do
    let(:actors) { %w[A B C D E F G] }
    let(:sections) { [["S", [["t", 3, actors]]]] }

    it "starts the dot colours over" do
      colours = scene.legend.map { |actor| actor.dot.colour }

      expect(colours.last).to eq(colours.first)
    end

    it "gives the first six actors six different colours" do
      colours = scene.legend.first(6).map { |actor| actor.dot.colour }

      expect(colours.uniq.length).to eq(6)
    end
  end

  context "with a three-line label" do
    let(:sections) { [["S", [["a<br/>b<br>c", 3, []]]]] }

    it "spreads the lines 14px apart around the box centre" do
      expect(scene.tasks.first.labels.map(&:y)).to eq([121.0, 135.0, 149.0])
    end
  end
end
