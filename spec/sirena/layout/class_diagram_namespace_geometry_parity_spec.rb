# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  subject(:scene) { described_class.new.call(parser.parse(source)) }

  let(:parser) { Sirena::Parser::ClassDiagram.new }

  context "with a relationship inside one namespace" do
    let(:source) { fixture("classdiagram_spec-20717dd9") }

    it "orders the related classes inside a fitted namespace" do
      expect(single_namespace_geometry)
        .to eq([true, [45.5], 1, [8.0, 8.0, 359.0, 159.0]])
    end
  end

  context "with relationships crossing two namespaces" do
    let(:source) { fixture("classdiagram_spec-2fe166c9") }

    it "keeps each namespace on one row and stacks the related groups" do
      expect(two_namespace_geometry).to eq([[33.0], [283.0], true])
    end
  end

  def single_namespace_geometry
    [classes_ordered?, class_rows, scene.namespaces.size, namespace_geometry]
  end

  def classes
    scene.children.to_h { |node| [node.id, node] }
  end

  def classes_ordered?
    classes.fetch("Admin").x < classes.fetch("User").x
  end

  def class_rows
    classes.values.map(&:y).uniq
  end

  def namespace_geometry
    box = scene.namespaces.fetch(0)
    [box.x, box.y, box.width, box.height]
  end

  def two_namespace_geometry
    [namespace_row("A"), namespace_row("B"), namespaces_stacked?]
  end

  def namespace_row(prefix)
    scene.children.select { |node| node.id.start_with?(prefix) }.map(&:y).uniq
  end

  def namespaces_stacked?
    namespaces = scene.namespaces.to_h { |box| [box.title, box] }
    namespaces.fetch("A").y < namespaces.fetch("B").y
  end

  def fixture(name)
    File.read("spec/mermaid/class_diagram/#{name}.mmd")
  end
end
