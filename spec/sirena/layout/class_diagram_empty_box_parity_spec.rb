# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  subject(:node) do
    diagram = Sirena::Parser::ClassDiagram.new.parse(source)
    described_class.new.call(diagram).children.first
  end

  {
    "classdiagram_spec-033a40d3" => ["A", 34.140625],
    "classdiagram_elk_v3_spec-29977982" => ["With (Brackets)", 139.078125],
  }.each do |case_name, (label, reference_width)|
    context "with #{case_name}" do
      let(:source) { "classDiagram\nclass C[\"#{label}\"]\n" }

      it "matches the pinned empty-class box dimensions" do
        width_error = (node.width - reference_width).abs / reference_width
        expect([width_error, node.height]).to match([be <= 0.15, 84.0])
      end
    end
  end
end
