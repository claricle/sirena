# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/xy_chart"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::XyChart from the native tree of the +xychart+
        # entry: native statements become the typed statements the Ruby
        # builder folds, and the parser assembles the diagram from that.
        class XyChart
          NUMERIC = /\A\d+(\.\d+)?\z/
          DATASETS = {
            line_values: [:line, "Line"],
            bar_values: [:bar, "Bar"],
          }.freeze
          private_constant :NUMERIC, :DATASETS

          # @param tree [Hash] native parse tree
          # @return [Diagram::XyChart]
          def apply(tree)
            statements = Text.items(tree[:statements]).filter_map do |item|
              statement(item)
            end
            result = Parser::Builders::XyChart.build(statements)
            Parser::XyChart.new.create_diagram(result)
          end

          private

          # Parslet leaves a statement with an empty quoted label
          # untransformed, and the Ruby builder ignores it.
          def statement(item)
            return if empty_label?(item)
            return title(item) if item.key?(:title)
            return x_axis(item) if item.key?(:x_values)
            return y_axis(item) if item.key?(:y_min)

            dataset(item)
          end

          def empty_label?(item)
            %i[title x_label y_label dataset_label].any? do |key|
              item.key?(key) && Text.empty?(item[key][:string])
            end
          end

          def title(item)
            { type: :title, title: item[:title][:string].to_s }
          end

          def x_axis(item)
            { type: :x_axis, label: label(item, :x_label),
              values: values(item[:x_values]) }
          end

          def y_axis(item)
            { type: :y_axis, label: label(item, :y_label),
              min: item[:y_min].to_s.to_f, max: item[:y_max].to_s.to_f }
          end

          def dataset(item)
            key, (chart_type, name) = DATASETS.find do |dataset_key, _|
              item.key?(dataset_key)
            end
            return named_dataset(item) unless key

            { type: :dataset, chart_type:, label: name,
              values: values(item[key]) }
          end

          def named_dataset(item)
            { type: :dataset, chart_type: :line,
              label: item[:dataset_label][:string].to_s,
              values: values(item[:dataset_values]) }
          end

          def label(item, key)
            item.key?(key) ? item[key][:string].to_s : nil
          end

          def values(node)
            Text.items(node).map do |entry|
              text = entry[:value].to_s
              text.match?(NUMERIC) ? text.to_f : text
            end
          end
        end
      end
    end
  end
end
