# frozen_string_literal: true

require "delegate"
require "logger"

module Sirena
  module Layout
    # A delegate around the logger elkrb reports through, minus its
    # "partially honoured" notices.
    #
    # Sirena hands elkrb only the options it acts on (see ElkPlacement).
    # Three of them, direction, alignment and node spacing, are only partly
    # honoured by elkrb across all its algorithms but fully for the layered
    # algorithm Sirena uses, so elkrb's notice for them is noise on every
    # layout. Every other message, at every level, reaches the wrapped
    # logger unchanged, whether that is elkrb's default or one the host
    # application assigned before loading Sirena.
    class ElkNotices < SimpleDelegator
      PARTIAL = /\Aelkrb: option \S+ is partially honoured/

      # Wraps the current Elkrb.logger once; a second call is a no-op.
      def self.install
        return if Elkrb.logger.is_a?(self)

        Elkrb.logger = new(Elkrb.logger)
      end

      def warn(message = nil, &block)
        return true if partial?(message || block&.call)

        __getobj__.warn(message, &block)
      end

      def add(severity, message = nil, progname = nil, &block)
        return true if partial?(message || progname || block&.call)

        __getobj__.add(severity, message, progname, &block)
      end
      alias log add

      private

      def partial?(text)
        text.is_a?(String) && PARTIAL.match?(text)
      end
    end
  end
end
