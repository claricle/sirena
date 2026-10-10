# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/pie"
require "sirena/notation/mermaid/ir_adapters/info"
require "sirena/notation/mermaid/ir_adapters/error"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Groups the data-shaped adapter contract in this spec.
        module DataTypes; end
      end
    end
  end
end

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::DataTypes do
  describe Sirena::Notation::Mermaid::IRAdapters::Pie do
    let(:diagram) do
      Sirena::Diagram::Pie.new(
        id: "slice_0", title: "Market share", show_data: true,
        acc_title: "Share by product", acc_description: "Current share",
        slices: [
          Sirena::Diagram::PieSlice.new(label: "Small", value: 1),
          Sirena::Diagram::PieSlice.new(label: "Large", value: 3),
        ]
      )
    end
    let(:ir) { described_class.call(diagram) }

    it "maps ordered values, visibility, and accessibility metadata" do
      expect(pie_attributes(ir)).to eq(expected_pie_attributes)
    end
  end

  describe Sirena::Notation::Mermaid::IRAdapters::Info do
    let(:diagram) do
      Sirena::Diagram::Info.new(
        id: "show_information", title: "Status", show_info: true,
      )
    end

    it "maps the show-information flag without colliding with the root" do
      ir = described_class.call(diagram)
      expect(info_attributes(ir)).to eq(expected_info_attributes)
    end
  end

  describe Sirena::Notation::Mermaid::IRAdapters::Error do
    let(:diagram) do
      Sirena::Diagram::Error.new(
        id: "message", title: "Failure", message: "Dependency missing",
      )
    end

    it "maps the message without colliding with the root" do
      ir = described_class.call(diagram)
      expect(error_attributes(ir)).to eq(expected_error_attributes)
    end
  end

  def pie_attributes(representation)
    pie_identity(representation) + [pie_values(representation)]
  end

  def pie_identity(representation)
    [representation.valid?, representation.id, representation.label,
     representation.accessibility_title,
     representation.accessibility_description,
     representation.dimensions.map(&:id)]
  end

  def pie_values(representation)
    representation.values.map do |value|
      [value.id, value.label, value.role, value.dimension_id,
       value.value.value]
    end
  end

  def expected_pie_attributes
    [true, "slice_0", "Market share", "Share by product", "Current share",
     ["category"],
     [["slice_0_2", "Small", "segment", "category", 1.0],
      ["slice_1", "Large", "segment", "category", 3.0],
      ["show_values", nil, "show_values", nil, true]]]
  end

  def info_attributes(representation)
    flag = representation.values.first
    [representation.valid?, representation.id, representation.label,
     representation.role,
     flag.id, flag.role, flag.value.value]
  end

  def expected_info_attributes
    [true, "show_information", "Status", "information_panel",
     "show_information_2", "show_information", true]
  end

  def error_attributes(representation)
    message = representation.items.first
    [representation.valid?, representation.id, representation.label,
     representation.role,
     message.id, message.label, message.role]
  end

  def expected_error_attributes
    [true, "message", "Failure", "error_panel",
     "message_2", "Dependency missing", "message"]
  end
end
