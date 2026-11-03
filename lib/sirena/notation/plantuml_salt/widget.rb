# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # One leaf of a salt row: plain text, a button, a text field and so on.
      class Widget
        KINDS = %i[text button field checkbox radio droplist empty].freeze

        attr_reader :kind, :runs, :checked

        # @param kind [Symbol] one of {KINDS}
        # @param runs [Array<Run>] the visible label, in order
        # @param checked [Boolean] whether a checkbox or radio is ticked
        def initialize(kind, runs = [], checked: false)
          @kind = kind
          @runs = runs.freeze
          @checked = checked
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
