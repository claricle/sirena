# frozen_string_literal: true

module Sirena
  # Renders an exception for a `--verbose` reader, following the `cause`
  # chain the engine deliberately leaves out of its messages.
  #
  # `Engine#render` raises `PipelineError` with `e.message` only, never
  # `e.backtrace`. A real stack overflow's backtrace ran to 1,044,280 bytes
  # for one measured bomb, and `BatchCommand` keeps every failure's message
  # for the length of the run, so baking the trace into the string
  # re-accumulated the very memory that guard exists to bound. Raising
  # inside the rescue chains the original on as `cause`, so nothing is lost
  # — it is simply one `.cause` away instead of inside every `#message`.
  #
  # Reading it back is this module's job. Without it `--verbose` shows a
  # trace that starts at the re-raise in `engine.rb` and omits the parser
  # frames that say what actually went wrong.
  module ErrorReport
    # How many frames of a CAUSE's backtrace to print.
    #
    # The top-level error's own trace is printed whole, because a wrapper
    # raised at a known line is short by construction. A cause is not: the
    # exhaustion path is exactly where a trace runs to six figures of
    # frames, and `--verbose` must stay readable on the failure it was most
    # needed for. The innermost frames are the ones that name the fault, so
    # the head of the trace is the part worth keeping.
    CAUSE_FRAME_LIMIT = 50

    module_function

    # Every cause below ERROR, deepest last, each with its class, message
    # and a bounded head of its backtrace.
    #
    # @param error [Exception]
    # @return [String] empty when ERROR has no cause
    def cause_diagnostics(error)
      causes(error).map { |cause| one_cause(cause) }.join("\n")
    end

    # @param error [Exception]
    # @return [Array<Exception>] the cause chain, nearest first
    def causes(error)
      chain = []
      seen  = [error.object_id]
      # A `cause` cycle is not reachable through `raise` today, but this
      # walks user-supplied exceptions and a loop here would hang the CLI
      # on the one code path whose whole purpose is surviving a bad input.
      while (error = error.cause) && !seen.include?(error.object_id)
        seen << error.object_id
        chain << error
      end
      chain
    end

    # @param cause [Exception]
    # @return [String]
    def one_cause(cause)
      # `backtrace` is nil when the VM fails an allocation before it can
      # build one, so verbose output must not assume there is a trace.
      frames = cause.backtrace || []
      shown  = frames.first(CAUSE_FRAME_LIMIT)
      omitted = frames.size - shown.size

      lines = ["Caused by: #{cause.class}: #{cause.message}", *shown]
      lines << "... #{omitted} more frames" if omitted.positive?
      lines.join("\n")
    end
  end
end
