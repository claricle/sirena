# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/kanban"

RSpec.describe Sirena::Layout::Kanban do
  subject(:scene) do
    diagram = Sirena::Parser::Kanban.new.parse(source)
    described_class.new.call(diagram)
  end

  context "with an empty column" do
    let(:source) { "kanban\n  todo[Todo]\n" }
    let(:geometry) do
      column = scene.columns.fetch(0)

      [scene.width, scene.height,
       [column.background.x, column.background.y,
        column.background.width, column.background.height],
       [column.header.x, column.header.y,
        column.header.width, column.header.height]]
    end

    it "reserves content space beneath the header" do
      expect(geometry).to eq(
        [280.0, 130.0, [40.0, 40.0, 200.0, 50.0],
         [40.0, 40.0, 200.0, 25.0]],
      )
    end
  end

  context "with one card" do
    let(:source) { "kanban\n  todo[Todo]\n    task[Task]\n" }
    let(:geometry) do
      column = scene.columns.fetch(0)
      card = scene.cards.fetch(0)

      [scene.width, scene.height,
       [column.background.width, column.background.height],
       [column.header.width, column.header.height],
       [card.background.x, card.background.y,
        card.background.width, card.background.height]]
    end

    it "preserves the existing geometry" do
      expect(geometry).to eq(
        [280.0, 159.0, [200.0, 79.0], [200.0, 25.0],
         [47.5, 65.0, 185.0, 44.0]],
      )
    end
  end
end
