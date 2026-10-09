# frozen_string_literal: true

require_relative "base"
require_relative "grammars/requirement"
require_relative "builders/requirement"
require_relative "../diagram/requirement"

module Sirena
  module Parser
    # Requirement diagram parser for Mermaid requirement diagram syntax.
    #
    # Parses requirement diagrams with support for:
    # - Requirements with properties (id, text, risk, verifymethod)
    # - Multiple requirement types (requirement, functionalRequirement, etc.)
    # - Elements with properties (type, docref)
    # - Relationships (contains, copies, derives, satisfies, verifies, refines, traces)
    # - Styling directives
    # - Class definitions and assignments
    #
    # @example Parse a simple requirement diagram
    #   parser = Requirement.new
    #   diagram = parser.parse("requirementDiagram\n  requirement test_req { id: 1 }")
    class Requirement < Base
      grammar Grammars::Requirement
      builder Builders::Requirement
    end
  end
end
