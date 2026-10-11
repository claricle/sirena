# frozen_string_literal: true

require "spec_helper"

module SequenceRendererClosureBranchesSpecHelpers
  def drawn_note_size(font_size)
    label = Sirena::Layout::Sequence::Label.new(text: "t", x: 1, y: 2,
                                                font_size: font_size)
    note = Sirena::Layout::Sequence::Note.new(x: 0, y: 0, width: 10,
                                              height: 10, lines: [label])
    Sirena::Renderer::Sequence::NoteDrawing.new(note).group.children
      .grep(Sirena::Svg::Text).first.font_size
  end
end

RSpec.describe Sirena::Renderer::Sequence do
  include SequenceRendererClosureBranchesSpecHelpers

  let(:layout) { Sirena::Layout::Sequence }
  let(:renderer) { described_class.new }

  describe "a box without a title" do
    let(:svg) { renderer.render(layout.new.call(parsed)) }
    let(:parsed) do
      Sirena::Parser::Sequence.new.parse(
        "sequenceDiagram\nbox Aqua\nparticipant A\nend\n",
      )
    end
    let(:box_group) { svg.children.find { |child| child.id == "box-0" } }

    it "draws only the outline" do
      expect(box_group.children.map(&:class_name)).to eq(["box"])
    end
  end

  describe "a frame whose title was not wrapped" do
    let(:frame) do
      layout::FrameShape.new(
        kind: "loop", x: 10, y: 10, width: 100, height: 60, title: "[go]",
        title_lines: [], title_x: 40, title_ys: [30], kind_x: 20, kind_y: 20,
        tab_points: "10,10 60,10 60,20 10,20"
      )
    end
    let(:group) do
      scene = layout::Scene.new(id: "s", width: 300, height: 200,
                                frames: [frame])
      renderer.render(scene).children
        .find { |child| child.id == "frame-0" }
    end

    it "draws the whole title as a single line" do
      expect(group.children.grep(Sirena::Svg::Text).flat_map(&:content)).to eq(%w[loop [go]])
    end
  end

  describe Sirena::Renderer::Sequence::NoteDrawing do
    {
      16.0 => "16",
      12.5 => "12.5",
    }.each do |size, expected|
      it "writes a #{size}px note text as #{expected}" do
        expect(drawn_note_size(size)).to eq(expected)
      end
    end
  end
end
