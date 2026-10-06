# frozen_string_literal: true

require_relative "sirena/version"
require_relative "sirena/error"
require_relative "sirena/error_report"

module Sirena
  # Faults a hostile DOCUMENT can provoke that are not `StandardError`, so
  # every ordinary rescue in this gem -- and in any host embedding it --
  # lets them past and the process goes down.
  #
  # Derived rather than collected a name at a time: every `Exception`
  # descendant loaded in this process that is not a `StandardError` was
  # enumerated and classified, and exactly these two are exhaustion caused
  # by the source being rendered. The rest are Ruby's own control flow
  # (`SystemExit`, `SignalException`, `Timeout::ExitException`, `fatal`),
  # a broken install (`ScriptError` and its subclasses), or `SecurityError`
  # -- none of which mean "this diagram failed to render", and three of
  # which MUST reach the caller or `exit`, Ctrl-C and a host's
  # `Timeout.timeout` stop working. That is why this is an allowlist of two
  # and not a `rescue Exception` with a list of exemptions.
  #
  # `spec/sirena/exhaustion_errors_spec.rb` enumerates the loaded hierarchy
  # and holds this list against it in the two directions a machine can
  # decide: every name here really is outside `StandardError`, and no
  # control-flow class is here. Whether a NEW class is exhaustion is a
  # judgement Ruby exposes no marker for, so no spec can make that call --
  # adding one to this list is a human decision, taken here.
  EXHAUSTION_ERRORS = [SystemStackError, NoMemoryError].freeze

  # Convenience method for rendering mermaid diagrams to SVG
  #
  # @param mermaid_source [String] Mermaid diagram source code
  # @param options [Hash] Rendering options
  # @return [String] SVG output
  def self.render(mermaid_source, options = {})
    Engine.new.render(mermaid_source, options)
  end
end
require_relative "sirena/notation/builtin"
