# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  subject(:renderer) { described_class.new }

  context "with retained filled-head calls" do
    let(:cases) do
      [[10, 90, 50, "90,50 82,46 82,54"],
       [90, 10, 50, "10,50 18,46 18,54"]]
    end
    let(:points) do
      cases.map do |start_x, end_x, end_y, _|
        group = Sirena::Svg::Group.new
        renderer.send(:render_filled_arrowhead,
                      start_x, 900, end_x, end_y, group)
        group.children.map(&:points)
      end
    end

    it "places one filled triangle at either directed endpoint" do
      expect(points).to eq(cases.map { |row| [row.last] })
    end
  end

  context "with retained cross calls" do
    let(:segments) do
      group = Sirena::Svg::Group.new
      renderer.send(:render_cross, 30, 70, group)
      group.children.map { |line| [line.x1, line.y1, line.x2, line.y2] }
    end

    it "draws both diagonals through the requested centre" do
      expect(segments).to eq([[26, 66, 34, 74], [26, 74, 34, 66]])
    end
  end

  context "with retained message-label calls" do
    let(:labels) do
      [[10, 90], [90, 10]].map do |start_x, end_x|
        group = Sirena::Svg::Group.new
        renderer.send(:render_message_label,
                      start_x, end_x, 50, "retained label", group)
        group.children.map { |text| [text.x, text.y, text.content] }
      end
    end

    it "centres unchanged label content ten pixels above either direction" do
      expect(labels).to eq(Array.new(2) { [[50, 40, ["retained label"]]] })
    end
  end
end
