# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # States of one container placed on one rank, left to right, each
        # with its note. A note and its target make one slot: the note at its
        # side and as much room on the other, so the targets of a column
        # stay in line however their notes fall.
        class Row
          GAP = 50.0
          NOTE_GAP = 30.0
          private_constant :GAP, :NOTE_GAP

          attr_reader :id, :nodes

          # @param nodes [Array<Hash>] the states, in order
          # @param notes [Hash{String=>Hash}] the note of a state by its id
          def initialize(nodes, notes)
            @nodes = nodes
            @notes = notes
            @id = nodes.size > 1 ? "row:#{nodes.first[:id]}" : nodes.first[:id]
          end

          def width
            @nodes.sum { |node| slot_width(node) } + (GAP * (@nodes.size - 1))
          end

          def height
            @nodes.map { |node| slot_height(node) }.max
          end

          # @return [Float] the left of the row's box
          def left
            first = @nodes.first
            note = @notes[first[:id]]
            first[:x] - (note ? note[:width] + NOTE_GAP : 0)
          end

          # Moves each state and note `shift` to the right.
          def slide(shift)
            @nodes.each do |node|
              node[:x] += shift
              @notes[node[:id]]&.then { |note| note[:x] += shift }
            end
          end

          # Writes the position of each state and note, the row's box at
          # `left`, `top`.
          def place(left, top)
            @nodes.each do |node|
              place_slot(node, left, top + ((height - slot_height(node)) / 2))
              left += slot_width(node) + GAP
            end
          end

          private

          def slot_width(node)
            note = @notes[node[:id]]
            return node[:width] unless note

            node[:width] + (2 * (note[:width] + NOTE_GAP))
          end

          def slot_height(node)
            [node[:height], @notes[node[:id]]&.fetch(:height).to_f].max
          end

          def place_slot(node, left, top)
            note = @notes[node[:id]]
            node[:y] = top + ((slot_height(node) - node[:height]) / 2)
            node[:x] = note ? left + note[:width] + NOTE_GAP : left
            place_note(node, note, left, top) if note
          end

          def place_note(node, note, left, top)
            beyond = node[:x] + node[:width] + NOTE_GAP
            leftward = note.dig(:metadata, :note_position) == "left"
            note[:x] = leftward ? left : beyond
            note[:y] = top + ((slot_height(node) - note[:height]) / 2)
          end
        end
      end
    end
  end
end
