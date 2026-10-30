# frozen_string_literal: true

require "logger"

module Sirena
  module Layout
    # The logger elkrb reports through, minus its "partially honoured"
    # notices.
    #
    # Sirena hands elkrb only the options it acts on (see ElkPlacement).
    # Three of them, direction, alignment and node spacing, are only partly
    # honoured by elkrb across all its algorithms but fully for the layered
    # algorithm Sirena uses, so elkrb's notice for them is noise on every
    # layout. Every other elkrb message goes through unchanged.
    class ElkNotices < Logger
      PARTIAL = /\Aelkrb: option \S+ is partially honoured/

      def add(severity, message = nil, progname = nil, &block)
        text = message || progname || block&.call
        return true if text.is_a?(String) && PARTIAL.match?(text)

        super
      end
    end
  end
end
