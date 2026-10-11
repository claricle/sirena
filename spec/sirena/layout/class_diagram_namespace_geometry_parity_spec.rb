# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  subject(:scene) { described_class.new.call(parser.parse(source)) }

  let(:parser) { Sirena::Parser::ClassDiagram.new }

  context "with a relationship inside one namespace" do
    let(:source) { fixture("classdiagram_spec-20717dd9") }

    it "orders the related classes inside a fitted namespace" do
      classes = scene.children.to_h { |node| [node.id, node] }
      box = scene.namespaces.fetch(0)

      expect([
        classes.fetch("Admin").x < classes.fetch("User").x,
        classes.values.map(&:y).uniq,
        scene.namespaces.size,
        [box.x, box.y, box.width, box.height],
      ]).to eq([true, [45.5], 1, [8.0, 8.0, 359.0, 159.0]])
    end
  end

  context "with relationships crossing two namespaces" do
    let(:source) { fixture("classdiagram_spec-2fe166c9") }

    it "keeps each namespace on one row and stacks the related groups" do
      rows = scene.children.group_by { |node| node.id[0] }
      namespaces = scene.namespaces.to_h { |box| [box.title, box] }

      expect([
        rows.fetch("A").map(&:y).uniq,
        rows.fetch("B").map(&:y).uniq,
        namespaces.fetch("A").y < namespaces.fetch("B").y,
      ]).to eq([[33.0], [283.0], true])
    end
  end

  def fixture(name)
    File.read("spec/mermaid/class_diagram/#{name}.mmd")
  end
end
