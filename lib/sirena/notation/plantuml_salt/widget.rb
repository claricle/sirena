# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # One leaf of a salt row: plain text, a button, a text field and so on.
      class Widget
        KINDS = %i[text button field checkbox radio droplist empty
                   rule].freeze

        attr_reader :kind, :runs, :checked, :items, :variant, :chars

        # @param kind [Symbol] one of {KINDS}
        # @param runs [Array<Run>] the visible label, in order
        # @param checked [Boolean] whether a checkbox or radio is ticked
        # @param extra [Hash] what only some kinds carry:
        # @option extra [Array<Array<Run>>] :items a droplist's further choices
        # @option extra [Symbol] :variant a rule's kind: `:dotted`, `:double`,
        #   `:solid` or `:heavy`
        # @option extra [Integer] :chars the characters the label took in the
        #   source, spaces included; PlantUML sizes a button, field or
        #   droplist by these
        def initialize(kind, runs = [], checked: false, **extra)
          @kind = kind
          @chars = extra.fetch(:chars) { runs.sum { |run| run.text.length } }
          @runs = runs.freeze
          @checked = checked
          @items = extra.fetch(:items, []).freeze
          @variant = extra[:variant]
          freeze
        end

        # @return [String] the label with its markup removed
        def text
          runs.map(&:text).join
        end
      end
    end
  end
end
