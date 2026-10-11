# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Mindmap, :aggregate_failures do
  subject(:scene) { described_class.new.call(parser.parse(source)) }

  let(:parser) { Sirena::Parser::Mindmap.new }

  context "with the multiline circles in knsv3-b01f9fc4" do
    let(:source) { fixture("knsv3-b01f9fc4") }

    it "caps the circle diameter at two lines without dropping label lines" do
      expect(multiline_circle_geometry)
        .to contain_exactly([68.0, 68.0, 2], [68.0, 68.0, 3])
    end
  end

  context "with the long unbreakable words in mindmap_spec-850ec74f" do
    let(:source) { fixture("mindmap_spec-850ec74f") }

    it "uses the longest word as the wrapping width" do
      expect(long_word_geometry).to eq(expected_long_word_geometry)
    end
  end

  def fixture(name)
    File.read("spec/mermaid/mindmap/#{name}.mmd")
  end

  def multiline_circle_geometry
    scene.children.select { |node| node.shape == "circle" }
      .select { |node| node.labels.first.lines.length > 1 }
      .map { |node| circle_geometry(node) }
  end

  def circle_geometry(node)
    [node.width, node.height, node.labels.first.lines.length]
  end

  def long_word_geometry
    root = scene.children.first
    [root.width, root.height, root.labels.first.lines.map(&:text)]
  end

  def expected_long_word_geometry
    [425.056, 116.0,
     ["A few smaller words but then ",
      "averylongsetofcharacterswithoutwhitespacetoseparate ",
      "that we expect to ",
      "wrapontonextlinesandnotexceedwidthparameters"]]
  end
end
