# frozen_string_literal: true

require_relative "appearance"
require_relative "fill"
require_relative "head_style"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Reads the colour and thickness skinparams PlantUML 1.2026.6 honours
        # on a sequence diagram, each probed against the JAR. A key it does
        # not list (`LifeLineBorderColor`, without `Sequence`, is one) makes
        # {.read} return nil, so the parser refuses the line.
        module Paint
          extend self

          ROLES = %i[head_fill head_line arrow lifeline box_fill box_line
                     divider_fill divider_line group_line note_fill
                     note_line background text_message_label text_note
                     text_box text_divider].freeze
          PAINTED = {
            "participantbackgroundcolor" => :head_fill,
            "participantbordercolor" => :head_line,
            "arrowcolor" => :arrow,
            "sequencelifelinebordercolor" => :lifeline,
            "sequenceboxbackgroundcolor" => :box_fill,
            "sequenceboxbordercolor" => :box_line,
            "sequencedividerbackgroundcolor" => :divider_fill,
            "sequencedividerbordercolor" => :divider_line,
            "sequencegroupbordercolor" => :group_line,
            "notebackgroundcolor" => :note_fill,
            "notebordercolor" => :note_line,
            "backgroundcolor" => :background,
            "arrowfontcolor" => :text_message_label,
            "notefontcolor" => :text_note,
            "sequenceboxfontcolor" => :text_box,
            "sequencedividerfontcolor" => :text_divider,
          }.freeze
          APPEARANCE = {
            "sequencegroupbackgroundcolor" => :tab_fill,
            "sequencegroupheaderfontcolor" => :tab_colour,
          }.freeze
          THICKNESS = /\A(?:\d+|\d*\.\d+)\z/
          private_constant :PAINTED, :APPEARANCE, :THICKNESS

          # @param key [String] the skinparam name, in any case
          # @param value [String] what follows it
          # @return [Appearance, nil] nil for a key or value not read
          def read(key, value)
            name = key.downcase.sub(/\Asequence(?=participant|arrow)/, "")
            return thickness(name, value) if name.end_with?("arrowthickness")

            colour = Fill.read(value.start_with?("#") ? value : "##{value}")
            return unless colour

            role_setting(name, key.downcase, colour.colour)
          end

          private

          def thickness(_name, value)
            Appearance.new(arrow_width: value) if THICKNESS.match?(value)
          end

          def role_setting(name, plain, colour)
            if PAINTED.key?(name)
              Appearance.new(paint: { PAINTED.fetch(name) => colour })
            elsif APPEARANCE.key?(plain)
              Appearance.new(APPEARANCE.fetch(plain) => colour)
            elsif name == "participantfontcolor"
              Appearance.new(head_style: HeadStyle.new(colour: colour))
            end
          end
        end
      end
    end
  end
end
