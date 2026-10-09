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
      #
      # @param timeout [Module] the Timeout module to read the unwinding
      #   class from
      # @return [Array<Class>]
      def self.passthrough_for(timeout)
        # Timeout::ExitException appeared after Ruby 3.2's bundled timeout;
        # there the unwinding exception is Timeout::Error itself.
        unwinding = if timeout.const_defined?(:ExitException)
                      timeout::ExitException
                    else
                      timeout::Error
                    end
        [NoMemoryError, SignalException, SystemExit, unwinding].freeze
      end

      PASSTHROUGH = passthrough_for(Timeout)
      private_constant :PASSTHROUGH

      # @param error [Exception]
      # @return [Boolean]
      def self.===(error)
        Exception === error && PASSTHROUGH.none? { |klass| klass === error }
      end
    end
  end
end
