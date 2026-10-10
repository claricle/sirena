# frozen_string_literal: true

require_relative "../../diagram/sequence_frame"
require_relative "../../diagram/sequence_box"
require_relative "sequence_box_title"

module Sirena
  module Parser
    module Builders
      # Walks the control blocks and `box` groups of a sequence diagram,
      # recording each as a frame or box on the model while the statements
      # inside still go through `process_statements`.
      #
      # Each block rule names its statement list with `.as`, so the key is
      # always present; the else/and/option continuations are a named
      # `repeat` (an Array, possibly empty) of hashes that name theirs.
      module SequenceBlocks
        private

        def reset_blocks
          @open_frames = []
          @event_order = 0
          @box_ids = nil
        end

        def process_box(diagram, stmt)
          box = Diagram::SequenceBox.new(
            **SequenceBoxTitle.split(decoded_text(stmt[:box_label])),
          )
          @box_ids = box.participant_ids
          process_statements(diagram, stmt[:box_statements])
          @box_ids = nil
          diagram.boxes << box
        end

        def process_loop(diagram, stmt)
          within_frame(diagram, "loop", stmt[:loop_label]) do
            process_statements(diagram, stmt[:loop_statements])
          end
        end

        def process_alt(diagram, stmt)
          within_frame(diagram, "alt", stmt[:alt_label]) do
            process_statements(diagram, stmt[:alt_statements])
            process_sections(diagram, stmt[:else_blocks], "else")
          end
        end

        def process_opt(diagram, stmt)
          within_frame(diagram, "opt", stmt[:opt_label]) do
            process_statements(diagram, stmt[:opt_statements])
          end
        end

        def process_rect(diagram, stmt)
          within_frame(diagram, "rect", stmt[:rect_label]) do
            process_statements(diagram, stmt[:rect_statements])
          end
        end

        def process_par(diagram, stmt)
          within_frame(diagram, "par", stmt[:par_label]) do
            process_statements(diagram, stmt[:par_statements])
            process_sections(diagram, stmt[:and_blocks], "and")
          end
        end

        def process_critical(diagram, stmt)
          within_frame(diagram, "critical", stmt[:critical_label]) do
            process_statements(diagram, stmt[:critical_statements])
            process_sections(diagram, stmt[:option_blocks], "option")
          end
        end

        def process_break(diagram, stmt)
          within_frame(diagram, "break", stmt[:break_label]) do
            process_statements(diagram, stmt[:break_statements])
          end
        end

        def within_frame(diagram, kind, label)
          frame = Diagram::SequenceFrame.new(
            kind: kind, label: decoded_text(label),
            start_index: @message_index, depth: @open_frames.length,
            open_order: next_order
          )
          diagram.frames << frame
          @open_frames.push(frame)
          yield
          close_frame(@open_frames.pop)
        end

        def close_frame(frame)
          frame.end_index = @message_index
          frame.close_order = next_order
        end

        def next_order
          @event_order += 1
        end

        # Each continuation names its own label and statement keys
        # (`else_label`/`else_statements`, `and_label`/...), all spelled
        # `<kind>_label` and `<kind>_statements`.
        def process_sections(diagram, blocks, kind)
          blocks.each do |block|
            @open_frames.last.sections << Diagram::SequenceFrameSection.new(
              kind: kind, label: decoded_text(block[:"#{kind}_label"]),
              start_index: @message_index, order: next_order
            )
            process_statements(diagram, block[:"#{kind}_statements"])
          end
        end
      end
    end
  end
end
