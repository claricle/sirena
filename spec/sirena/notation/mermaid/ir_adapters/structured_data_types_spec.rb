# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/kanban"
require "sirena/notation/mermaid/ir_adapters/radar"
require "sirena/notation/mermaid/ir_adapters/treemap"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Shared contract namespace for structured-data adapter specs.
        module StructuredDataTypes; end
      end
    end
  end
end

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::StructuredDataTypes do
  describe Sirena::Notation::Mermaid::IRAdapters::Kanban do
    subject(:adapter_evidence) do
      data = described_class.call(diagram)
      items = data.items.map do |item|
        [item.id, item.label, item.role, item.parent_id]
      end
      values = data.values.map do |value|
        [value.role, value.parent_id, value.value.value]
      end
      [data.valid?, data.id, data.label, data.role, items, values]
    end

    let(:diagram) do
      card = Sirena::Diagram::KanbanCard.new(
        id: "work", text: "Ship it", assigned: "Alice", ticket: "S-1",
        icon: "rocket", label: "Release", priority: "High",
        classes: %w[urgent blocked]
      )
      column = Sirena::Diagram::KanbanColumn.new(
        id: "todo", title: "Todo", icon: "list", classes: ["planned"],
        cards: [card]
      )
      Sirena::Diagram::Kanban.new(
        id: "work", title: "Board", columns: [column],
      )
    end
    let(:expected_evidence) do
      [true, "work_2", "Board", "work_board",
       [["todo", "Todo", "board_column", nil],
        ["work", "Ship it", "work_item", "todo"]],
       [["icon", "todo", "list"],
        ["style_reference", "todo", "planned"],
        ["assignee", "work", "Alice"],
        ["ticket_reference", "work", "S-1"],
        ["icon", "work", "rocket"],
        ["secondary_label", "work", "Release"],
        ["priority", "work", "High"],
        ["style_reference", "work", "urgent"],
        ["style_reference", "work", "blocked"]]]
    end

    it { is_expected.to eq(expected_evidence) }

    context "when Mermaid repeats a card identifier across columns" do
      subject(:adapter_evidence) do
        data = described_class.call(diagram)
        items = data.items.map { |item| [item.id, item.parent_id] }
        assigned = data.values.find { |value| value.role == "assignee" }

        [data.valid?, items, assigned.parent_id]
      end

      let(:diagram) do
        first = Sirena::Diagram::KanbanColumn.new(
          id: "todo", title: "Todo",
          cards: [Sirena::Diagram::KanbanCard.new(id: "docs", text: "Write")]
        )
        second = Sirena::Diagram::KanbanColumn.new(
          id: "doing", title: "Doing",
          cards: [Sirena::Diagram::KanbanCard.new(
            id: "docs", text: "Publish", assigned: "Alice",
          )]
        )
        Sirena::Diagram::Kanban.new(columns: [first, second])
      end

      let(:expected_evidence) do
        [true,
         [["todo", nil], ["docs", "todo"],
          ["doing", nil], ["docs_2", "doing"]],
         "docs_2"]
      end

      it { is_expected.to eq(expected_evidence) }
    end
  end

  describe Sirena::Notation::Mermaid::IRAdapters::Radar do
    subject(:adapter_evidence) do
      data = described_class.call(diagram)
      measurements, options = data.values.partition do |value|
        value.role == "measurement"
      end
      dimensions = data.dimensions.map do |axis|
        [axis.id, axis.label, axis.role]
      end
      series = data.series.map { |entry| [entry.id, entry.label, entry.role] }
      readings = measurements.map do |value|
        [value.dimension_id, value.series_id, value.value.value]
      end
      settings = options.map { |value| [value.role, value.value.value] }
      [data.valid?, data.id, data.label, data.accessibility_title,
       data.accessibility_description, dimensions, series, readings, settings]
    end

    let(:diagram) do
      Sirena::Diagram::Radar.new.tap do |radar|
        radar.id = "radar"
        radar.title = "Tradeoffs"
        radar.acc_title = "Comparison"
        radar.acc_descr = "Speed and quality"
        radar.axes = [
          Sirena::Diagram::RadarAxis.new("speed", "Speed"),
          Sirena::Diagram::RadarAxis.new("quality", "Quality"),
        ]
        radar.curves = [radar_curve]
        radar.options = {
          min: 0, max: 10, ticks: 5, show_legend: false,
          graticule: "polygon"
        }
      end
    end
    let(:radar_curve) do
      Sirena::Diagram::RadarCurve.new("current", "Current").tap do |curve|
        curve.add_value("speed", 8)
      end
    end
    let(:expected_evidence) do
      [true, "radar", "Tradeoffs", "Comparison", "Speed and quality",
       [["speed", "Speed", "axis"], ["quality", "Quality", "axis"]],
       [["current", "Current", "dataset"]],
       [["speed", "current", 8.0], ["quality", "current", 0.0]],
       [["lower_bound", 0.0], ["upper_bound", 10.0],
        ["tick_count", 5.0], ["legend_visibility", false],
        ["grid_shape", "polygon"]]]
    end

    it { is_expected.to eq(expected_evidence) }

    context "when an axis and series request the same identifier" do
      subject(:adapter_evidence) do
        data = described_class.call(diagram)
        identifier = data.values.find { |value| value.role == "identifier" }
        [data.valid?, data.dimensions.first.id, data.series.first.id,
         identifier.parent_id, identifier.value.value]
      end

      let(:diagram) do
        Sirena::Diagram::Radar.new.tap do |radar|
          radar.axes = [Sirena::Diagram::RadarAxis.new("same", "Axis")]
          radar.curves = [Sirena::Diagram::RadarCurve.new("same", "Curve")]
        end
      end
      let(:expected_evidence) { [true, "same", "same_2", "same_2", "same"] }

      it { is_expected.to eq(expected_evidence) }
    end
  end

  describe Sirena::Notation::Mermaid::IRAdapters::Treemap do
    subject(:adapter_evidence) do
      data = described_class.call(diagram)
      partitions = data.series.map do |series|
        [series.id, series.label, series.role, series.parent_id]
      end
      values = data.values.map do |value|
        [value.role, value.label, value.series_id, value.value.value]
      end
      dimensions = data.dimensions.map do |dimension|
        [dimension.id, dimension.role]
      end
      [data.valid?, data.id, data.label, data.role,
       dimensions, partitions, values]
    end

    let(:diagram) do
      Sirena::Diagram::Treemap.new.tap do |treemap|
        treemap.id = "partition_0"
        treemap.title = "Allocation"
        root = Sirena::Diagram::TreemapNode.new("Root")
        child = Sirena::Diagram::TreemapNode.new("Child", 12.5)
        child.css_class = "important"
        root.add_child(child)
        treemap.add_root_node(root)
        treemap.add_class_def("important", "fill:#f96,stroke:#333")
      end
    end
    let(:expected_evidence) do
      [true, "partition_0_2", "Allocation", "hierarchical_partition",
       [["magnitude", "magnitude"]],
       [["partition_0", "Root", "partition", nil],
        ["partition_0_0", "Child", "partition", "partition_0"]],
       [["magnitude", nil, "partition_0_0", 12.5],
        ["style_reference", nil, "partition_0_0", "important"],
        ["fill_color", "important", nil, "#f96"],
        ["stroke_color", "important", nil, "#333"]]]
    end

    it { is_expected.to eq(expected_evidence) }
  end
end
