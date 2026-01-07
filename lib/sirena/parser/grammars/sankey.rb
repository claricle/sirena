# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Sankey diagrams.
      #
      # Handles Sankey diagram syntax including flows (CSV format) and
      # optional node declarations with labels.
      #
      # @example Simple Sankey
      #   sankey-beta
      #   A,B,10
      #   B,C,20
      #
      # @example Sankey with node labels
      #   sankey-beta
      #   Source [Energy Source]
      #   Process [Processing Plant]
      #   Source,Process,100
      #   Process,Output,70
      class Sankey < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # Header: sankey-beta
        rule(:header) do
          str("sankey-beta").as(:header) >> ws?
        end

        # Statements (node declarations and flow entries)
        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          node_declaration |
            flow_entry |
            comment >> line_end
        end

        # Node declaration with optional label
        # Example: NodeID [Node Label]
        rule(:node_declaration) do
          (space? >>
            node_id.as(:node_id) >>
            space? >>
            lbracket >>
            (rbracket.absent? >> any).repeat(1).as(:node_label) >>
            rbracket >>
            line_end).as(:node_declaration)
        end

        # Flow entry: source,target,value
        # Example: A,B,10.5
        rule(:flow_entry) do
          (space? >>
            node_id.as(:source) >>
            space? >> comma >> space? >>
            node_id.as(:target) >>
            space? >> comma >> space? >>
            flow_value.as(:value) >>
            line_end).as(:flow_entry)
        end

        # Node identifier (alphanumeric, underscores, dashes)
        rule(:node_id) do
          match["a-zA-Z0-9_-"].repeat(1)
        end

        # Flow value (integer or float)
        rule(:flow_value) do
          match["0-9"].repeat(1) >>
            (str(".") >> match["0-9"].repeat(1)).maybe
        end

        # Comma separator
        rule(:comma) do
          str(",")
        end

        # Left bracket
        rule(:lbracket) do
          str("[")
        end

        # Right bracket
        rule(:rbracket) do
          str("]")
        end
      end
    end
  end
end