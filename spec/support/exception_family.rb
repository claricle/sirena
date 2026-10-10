# frozen_string_literal: true

require "cgi"
require "timeout"

# Every Exception class loaded in this process, so a spec about "any
# exception" is a table of what exists and not of the routes someone
# thought of.
module ExceptionFamily
  TIMEOUT_UNWINDING = if Timeout.const_defined?(:ExitException, false)
                        Timeout::ExitException
                      else
                        Timeout::Error
                      end

  # What a plugin's failure must never swallow: the process's and the
  # host's own unwinding. A spec's own list, so editing the library's
  # cannot move it.
  PASSTHROUGH = [
    NoMemoryError, SignalException, SystemExit, TIMEOUT_UNWINDING
  ].freeze

  # The timeout gem added ExitException after Ruby 3.2's bundled version.
  # Older Timeout::Error instances unwind with throw, so exercise that real
  # path instead of raising the fallback class directly.
  def self.timeout_passthrough?
    if Timeout.const_defined?(:ExitException, false)
      error = TIMEOUT_UNWINDING.new("too slow")
      yield error
      false
    else
      swallowed = Object.new
      result = Timeout::Error.catch do |error|
        yield error
        swallowed
      end
      !result.equal?(swallowed)
    end
  rescue TIMEOUT_UNWINDING => e
    e.equal?(error)
  end

  # Named classes only, so each example has a stable title. An instance is
  # built with `allocate` because constructors disagree on arguments; a
  # class whose bare instance cannot report its #message (it needs
  # constructor state) is left out, because the engine reads the message.
  def self.all
    walk(Exception).select do |klass|
      klass.name && usable?(klass.allocate)
    end
  end

  def self.usable?(error)
    error.exception.equal?(error) && error.message.is_a?(String)
  rescue StandardError
    false
  end
  private_class_method :usable?

  def self.passing
    all.select { |klass| passthrough?(klass) }
  end

  def self.failing
    all - passing
  end

  def self.passthrough?(klass)
    PASSTHROUGH.any? { |kind| klass <= kind }
  end

  def self.walk(klass)
    [klass] + klass.subclasses.flat_map { |child| walk(child) }
  end
  private_class_method :walk
end
