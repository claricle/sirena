# frozen_string_literal: true

require_relative "base"
require_relative "grammars/state_diagram"
require_relative "builders/state_diagram"
require_relative "../diagram/state_diagram"

module Sirena
  module Parser
    # State diagram parser for Mermaid state diagram syntax.
    #
    # Parses state diagrams with support for:
    # - Normal states with labels
    # - Special states (start [*], end [*], choice, fork, join)
    # - Transitions with triggers and guard conditions
    # - Composite/nested states
    # - Direction statements (TB, BT, LR, RL)
    #
    # @example Parse a simple state diagram
    #   parser = StateDiagram.new
    #   diagram = parser.parse("stateDiagram-v2\n[*]-->Idle\nIdle-->Active")
    class StateDiagram < Base
      grammar Grammars::StateDiagram
      builder Builders::StateDiagram
    end
  end
end
