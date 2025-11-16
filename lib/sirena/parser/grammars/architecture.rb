# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for architecture diagrams
      class Architecture < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
          header >>
          ws? >>
          statements.maybe >>
          ws?
        end

        rule(:header) do
          str("architecture-beta").as(:header)
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          title_statement |
          acc_title_statement |
          acc_descr_statement |
          group_def |
          service_def |
          edge_def
        end

        # Title statement
        rule(:title_statement) do
          str("title") >> space.repeat(1) >>
          (line_end.absent? >> any).repeat(1).as(:title) >>
          line_end
        end

        # Accessibility title
        rule(:acc_title_statement) do
          str("accTitle:") >> space.repeat(1) >>
          (line_end.absent? >> any).repeat(1).as(:acc_title) >>
          line_end
        end

        # Accessibility description
        rule(:acc_descr_statement) do
          str("accDescr:") >> space.repeat(1) >>
          (line_end.absent? >> any).repeat(1).as(:acc_descr) >>
          line_end
        end

        # Group definition
        rule(:group_def) do
          str("group").as(:stmt_type) >> space.repeat(1) >>
          arch_identifier.as(:id) >>
          icon_spec.maybe >>
          label_spec.maybe >>
          in_clause.maybe.as(:parent) >>
          line_end
        end

        # Service definition
        rule(:service_def) do
          str("service").as(:stmt_type) >> space.repeat(1) >>
          arch_identifier.as(:id) >>
          icon_spec >>
          label_spec >>
          in_clause.maybe.as(:group) >>
          line_end
        end

        # Edge definition - handles various formats
        # Format: from:fromPos --> toPos:to or from --> to
        rule(:edge_def) do
          arch_identifier.as(:from) >>
          position_spec.maybe.as(:from_pos) >>
          space? >>
          arrow.as(:arrow) >>
          space? >>
          (reverse_position_spec.as(:to_pos) >> colon).maybe >>
          arch_identifier.as(:to) >>
          (space? >> colon >> space? >> edge_label.as(:label)).maybe >>
          line_end
        end

        # Reverse position spec: L: instead of :L (for target position)
        rule(:reverse_position_spec) do
          match("[LRTB]").repeat(1)
        end

        # Icon specification
        rule(:icon_spec) do
          lparen >> icon_content.as(:icon) >> rparen
        end

        rule(:icon_content) do
          (rparen.absent? >> any).repeat(1)
        end

        # Label specification
        rule(:label_spec) do
          lbracket >> label_content.as(:label) >> rbracket
        end

        rule(:label_content) do
          (rbracket.absent? >> any).repeat(1)
        end

        # In clause for group membership
        rule(:in_clause) do
          space.repeat(1) >> str("in") >> space.repeat(1) >> arch_identifier.as(:group_id)
        end

        # Position specification (e.g., :L, :R, :T, :B)
        rule(:position_spec) do
          colon >> match("[LRTB]").repeat(1).as(:pos_value)
        end

        # Arrow patterns - order matters, check longer first
        rule(:arrow) do
          str("L--R") | str("R--L") |
          str("T--B") | str("B--T") |
          str("-->") | str("--")
        end

        # Edge label
        rule(:edge_label) do
          (line_end.absent? >> any).repeat(1)
        end

        # Architecture-specific identifier (allows hyphens and numbers)
        rule(:arch_identifier) do
          match("[a-zA-Z0-9_-]").repeat(1)
        end
      end
    end
  end
end