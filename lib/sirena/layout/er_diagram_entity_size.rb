# frozen_string_literal: true

require_relative "../text_measurement/trebuchet_advances"

module Sirena
  module Layout
    # Sizes an entity box the way mmdc's erBox does: a name row above one row
    # per attribute, with the type, name, key and comment columns each as wide
    # as their widest cell. Text is measured as Trebuchet MS at 16px, the face
    # mmdc measured with.
    #
    # The numbers are mmdc's defaults after its 1.25 scale for non-HTML
    # labels: diagramPadding 20 and entityPadding 15 become PADDING and
    # TEXT_PADDING, and a text line is 24px tall.
    module ErDiagramEntitySize
      FONT_SIZE = 16
      TEXT_HEIGHT = 24
      PADDING = 25
      TEXT_PADDING = 18.75
      ROW_HEIGHT = TEXT_HEIGHT + TEXT_PADDING
      # An entity with no attributes is a plain padded label box instead.
      LABEL_PADDING_X = 20
      LABEL_PADDING_Y = 30
      MIN_ENTITY_WIDTH = 100
      TABLE = TextMeasurement::TrebuchetAdvances::TABLE
      private_constant :TABLE

      module_function

      # @param name [String] the entity name
      # @param attributes [Array<Hash>] cells under :attribute_type, :name,
      #   :key_type and :note
      # @return [Hash] :width and :height of the box
      def call(name, attributes)
        return label_box(name) if attributes.empty?

        cells = cell_texts(attributes)
        {
          width: [column_widths(cells).sum,
                  text_width(name) + (PADDING * 2),
                  cells.flatten.map { |cell| text_width(cell) }.max +
                    (PADDING * 2)].max,
          height: ROW_HEIGHT * (attributes.length + 1),
        }
      end

      # @return [Float] the width of one line of text
      def text_width(text)
        text.to_s.each_char.sum { |char| TABLE.fetch(char.ord, 1000) } *
          FONT_SIZE / 1000.0
      end

      def label_box(name)
        width = text_width(name) + (LABEL_PADDING_X * 2)
        {
          width: [width, MIN_ENTITY_WIDTH].max.to_f,
          height: TEXT_HEIGHT + (LABEL_PADDING_Y * 2),
        }
      end

      def cell_texts(attributes)
        attributes.map do |attribute|
          [attribute[:attribute_type], attribute[:name],
           attribute[:key_type].to_s.split(/\s*,\s*/).join(","),
           attribute[:note]]
        end
      end

      # The type and name columns always count; the key and comment columns
      # vanish when no attribute fills them.
      def column_widths(cells)
        cells.transpose.each_with_index.map do |column, index|
          widest = column.map { |cell| text_width(cell) }.max + PADDING
          index >= 2 && widest <= PADDING ? 0 : widest
        end
      end
      private_class_method :label_box, :cell_texts, :column_widths
    end
  end
end
