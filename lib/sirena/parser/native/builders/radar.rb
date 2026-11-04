# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/radar"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Radar from the native tree of the +radar+ entry:
        # native statements become the typed statements the Ruby builder
        # folds, and the parser assembles the diagram from that.
        class Radar
          SCALARS = %i[title acc_title acc_descr].freeze
          OPTIONS = {
            ticks: :to_i.to_proc,
            show_legend: ->(text) { text == "true" },
            graticule: :to_s.to_proc,
            min: :to_f.to_proc,
            max: :to_f.to_proc,
          }.freeze
          private_constant :SCALARS, :OPTIONS

          # @param tree [Hash] native parse tree
          # @return [Diagram::Radar]
          def apply(tree)
            statements = Text.items(tree[:statements]).filter_map do |item|
              statement(item)
            end
            result = Parser::Builders::Radar.build(statements)
            Parser::Radar.new.create_diagram(result)
          end

          private

          def statement(item)
            scalar = SCALARS.find { |key| item.key?(key) }
            return { type: scalar, scalar => item[scalar].to_s } if scalar
            return axes(item) if item.key?(:axes)
            return curve(item) if item.key?(:values)

            option(item)
          end

          def axes(item)
            list = Text.items(item[:axes]).map { |axis| axis_entry(axis) }
            { type: :axes, axes: list }
          end

          def axis_entry(axis)
            id = axis[:id].to_s
            { id:, label: axis.key?(:label) ? axis[:label].to_s : id }
          end

          def curve(item)
            id = item[:id].to_s
            { type: :curve, id:,
              label: item.key?(:label) ? item[:label].to_s : id,
              values: values(item[:values]) }
          end

          # One value is a bare number or hash, several an Array, as the
          # Ruby builder leaves them.
          def values(node)
            list = Text.items(node).map { |entry| value(entry) }
            list.one? ? list.first : list
          end

          def value(entry)
            number = entry[:value].to_s.to_f
            return number unless entry.key?(:axis)

            { axis: entry[:axis].to_s, value: number }
          end

          def option(item)
            key = OPTIONS.keys.find { |name| item.key?(name) }
            { type: :option, key:, value: OPTIONS[key].call(item[key].to_s) }
          end
        end
      end
    end
  end
end
