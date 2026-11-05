# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Network
        # Where each node sits: the network it first appears in (its box
        # hangs just below that bar), the last one it reaches, and a column
        # no other node uses in the same stretch.
        class Placement
          Span = Struct.new(:name, :entry, :exit, :column,
                            keyword_init: true) do
            # The gaps between bars the node's box and line pass through.
            def gaps
              (entry..[exit - 1, entry].max).to_a
            end
          end

          # @param diagram [Diagram]
          def initialize(diagram)
            @spans = spans_of(diagram).each_with_object([]) do |span, placed|
              span.column = free_column(placed, span)
              placed << span
            end
            @by_name = @spans.to_h { |span| [span.name, span] }
          end

          # @return [Array<Span>] in order of first appearance
          attr_reader :spans

          # @return [Span]
          def [](name)
            @by_name.fetch(name)
          end

          # @return [Integer]
          def columns
            (@spans.map(&:column).max || -1) + 1
          end

          private

          def spans_of(diagram)
            rows = {}
            diagram.networks.each_with_index do |network, index|
              network.nodes.each do |member|
                span = (rows[member.name] ||= Span.new(
                  name: member.name, entry: index, exit: index,
                ))
                span.exit = index
              end
            end
            rows.values
          end

          def free_column(placed, span)
            taken = placed.select { |other| other.gaps.intersect?(span.gaps) }
            (0..).find { |column| taken.none? { |t| t.column == column } }
          end
        end
      end
    end
  end
end
