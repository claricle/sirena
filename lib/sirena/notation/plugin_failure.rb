# frozen_string_literal: true

require "timeout"

module Sirena
  module Notation
    # Matches, in a `rescue`, whatever running a plugin can raise that is
    # not the process's or the host's to handle: every Exception except
    # the ones below. A list of classes to rescue goes stale the first time
    # a dependency raises a direct Exception subclass (CGI::InvalidEncoding);
    # this names the exceptions that must pass instead.
    #
    #   rescue PluginFailure => e
    module PluginFailure
      # Out of memory, signals (Interrupt included), exit, and the exception
      # `Timeout.timeout` unwinds a host's block with.
      PASSTHROUGH = [
        NoMemoryError, SignalException, SystemExit, Timeout::ExitException
      ].freeze
      private_constant :PASSTHROUGH

      # @param error [Exception]
      # @return [Boolean]
      def self.===(error)
        Exception === error && PASSTHROUGH.none? { |klass| klass === error }
      end
    end
  end
end
