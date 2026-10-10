# frozen_string_literal: true

require_relative "../base"
require_relative "../../svg"

module Sirena
  module Renderer
    class Sequence < Base
      # Draws one positioned note: mermaid's default note colours, a box and
      # one text element per line.
      class NoteDrawing
        FILL = "#fff5ad"
        STROKE = "#aaaa33"

        # @param note [Layout::Sequence::Note] a positioned note
        def initialize(note)
          @note = note
        end

        # @return [Svg::Group] the note box with its text lines
        def group
          Svg::Group.new.tap do |item|
            item.children << box
            @note.lines.each { |line| item.children << text(line) }
          end
        end

        private

        def box
          Svg::Rect.new.tap do |rect|
            rect.x = @note.x
            rect.y = @note.y
            rect.width = @note.width
            rect.height = @note.height
            style_box(rect)
          end
        end

        def style_box(rect)
          rect.fill = FILL
          rect.stroke = STROKE
          rect.stroke_width = "1"
        end

        def size(value)
          value.to_i == value ? value.to_i.to_s : value.to_s
        end

        def text(line)
          Svg::Text.new.tap do |item|
            item.x = line.x
            item.y = line.y
            item.content = line.text
            item.font_size = size(line.font_size)
            style_text(item)
          end
        end

        def style_text(item)
          item.fill = "#000000"
          item.font_family = "Arial, sans-serif"
          item.text_anchor = "middle"
          item.dominant_baseline = "middle"
        end
      end
    end
  end
end
