# frozen_string_literal: true

require_relative '../error'

module Sirena
  module Parser
    # Error raised during parsing. A Sirena::Error so Engine#render can let
    # it propagate unwrapped instead of collapsing it into PipelineError.
    class ParseError < Sirena::Error; end
  end
end
