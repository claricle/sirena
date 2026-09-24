# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Requirement diagrams.
      #
      # Handles requirement diagram syntax including requirements, elements,
      # relationships, styling, and class assignments.
      class Requirement < Common
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
          str('requirementDiagram').as(:header) >> ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          acc_title_declaration |
            acc_descr_declaration |
            requirement_statement |
            element_statement |
            relationship_statement |
            style_statement |
            class_definition_statement |
            class_assignment_statement
        end

        # JS's `\s` (what mermaid's own accTitle/accDescr lexer tokens use)
        # is wider than ASCII space/tab/newline. Ruby's `[[:space:]]` is not
        # the same set: it misses U+FEFF and adds U+0085, so spell out the JS
        # characters here.
        # `whitespace?` from Common (`lib/sirena/parser/grammars/common.rb`)
        # is ASCII-only and out of scope to widen here (common.rb is shared
        # by every diagram type); this local override shadows it for the
        # three accTitle/accDescr rules below only.
        ACC_WHITESPACE_CHARS = '\t\v\f\r\n\x20\u00A0\u1680' \
          '\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF'
        private_constant :ACC_WHITESPACE_CHARS

        rule(:whitespace?) { match[ACC_WHITESPACE_CHARS].repeat }

        # Accessibility title. Mermaid's lexer token is a SINGLE regex,
        # `accTitle\s*":"\s*` -- \s matches a newline (so the colon and the
        # value after it may start on the line after the keyword) but NOT a
        # `%%` comment, which isn't part of `\s` and has no rule of its own
        # inside this token. `whitespace?` (whitespace only, no comment)
        # mirrors that; the full comment-aware `ws?` would wrongly accept
        # `accTitle%% c\n: T`, which this token can't match at all upstream.
        #
        # `.repeat(1)`, not `.repeat`: mermaid's lexer token requires the
        # value to be non-empty (verified against mermaid 11.12.0 --
        # `"accTitle:\n"` with nothing after is a parse error there, not an
        # empty title; `\s*` only skips leading blank lines before a
        # mandatory value). `.repeat` (0+) would accept and silently emit
        # `''`, matching nothing mermaid can actually produce.
        rule(:acc_title_declaration) do
          str('accTitle') >> whitespace? >> colon >> whitespace? >>
            (newline.absent? >> any).repeat(1).as(:acc_title) >>
            (newline | eof)
        end

        # Accessibility description (single or multi-line)
        rule(:acc_descr_declaration) do
          acc_descr_single_line | acc_descr_multi_line
        end

        # `.repeat(1)` for the same reason as acc_title_declaration above:
        # mermaid errors on `"accDescr:\n"` with nothing after rather than
        # producing an empty description (verified against 11.12.0). The
        # brace form below (`accDescr {}`) is a different lexer token and
        # DOES allow an empty value there -- confirmed separately -- so it
        # keeps `.repeat` (0+).
        rule(:acc_descr_single_line) do
          str('accDescr') >> whitespace? >> colon >> whitespace? >>
            (newline.absent? >> any).repeat(1).as(:acc_descr) >>
            (newline | eof)
        end

        # Mermaid's multiline lexer token is likewise the single regex
        # `accDescr\s*"{"\s*` (whitespace only, no comment), so the opening
        # brace may also start on a later line than the keyword. Its body
        # state (`[^\}]*`) is popped by `}` alone -- the grammar never
        # requires a NEWLINE after that closing brace, so a statement may
        # follow immediately on the same line (`accDescr {x}accTitle: y`
        # parses both directives upstream). No `line_end` after `rbrace`
        # here: the enclosing `statements` rule's own `ws?` absorbs
        # whatever separates this from the next statement, including none.
        rule(:acc_descr_multi_line) do
          str('accDescr') >> whitespace? >> lbrace >> whitespace? >>
            (rbrace.absent? >> any).repeat.as(:acc_descr) >>
            rbrace
        end

        # Requirement: requirement [type] name { properties }
        # or: functionalRequirement name { properties }
        rule(:requirement_statement) do
          requirement_keyword.as(:req_type) >>
            space >>
            identifier.as(:req_name) >>
            (ws? >> class_shorthand.as(:req_classes)).maybe >>
            ws? >>
            lbrace >>
            ws? >>
            properties.maybe.as(:req_properties) >>
            ws? >>
            rbrace >>
            line_end
        end

        rule(:requirement_keyword) do
          str('functionalRequirement') |
            str('interfaceRequirement') |
            str('performanceRequirement') |
            str('physicalRequirement') |
            str('designConstraint') |
            str('requirement')
        end

        # Element: element name { properties }
        rule(:element_statement) do
          str('element').as(:elem_keyword) >>
            space >>
            identifier.as(:elem_name) >>
            (ws? >> class_shorthand.as(:elem_classes)).maybe >>
            ws? >>
            lbrace >>
            ws? >>
            properties.maybe.as(:elem_properties) >>
            ws? >>
            rbrace >>
            line_end
        end

        # Properties: key: value pairs
        rule(:properties) do
          (property >> ws?).repeat(1)
        end

        rule(:property) do
          property_key.as(:key) >>
            ws? >>
            colon >>
            ws? >>
            property_value.as(:value) >>
            line_end
        end

        rule(:property_key) do
          (str('id') | str('text') | str('risk') | str('verifymethod') |
           str('type') | str('docref')).as(:prop_key)
        end

        rule(:property_value) do
          (line_end.absent? >> any).repeat(1)
        end

        # Relationship: source - type -> target
        rule(:relationship_statement) do
          identifier.as(:rel_source) >>
            ws? >>
            str('-') >>
            ws? >>
            relationship_type.as(:rel_type) >>
            ws? >>
            str('->') >>
            ws? >>
            identifier.as(:rel_target) >>
            line_end
        end

        rule(:relationship_type) do
          (str('contains') | str('copies') | str('derives') |
           str('satisfies') | str('verifies') | str('refines') |
           str('traces')).as(:type)
        end

        # Style: style target1 [target2 ...] fill:#f9f,stroke:#333
        rule(:style_statement) do
          str('style').as(:style_keyword) >> space >>
            style_targets.as(:style_targets) >> space >>
            style_properties.as(:style_props) >>
            line_end
        end

        rule(:style_targets) do
          identifier >> (comma >> ws? >> identifier).repeat
        end

        rule(:style_properties) do
          style_property >> (comma >> style_property).repeat
        end

        rule(:style_property) do
          (line_end.absent? >> comma.absent? >> any).repeat(1)
        end

        # Class definition: classDef className fill:#f9f,stroke:#333
        rule(:class_definition_statement) do
          str('classDef').as(:classdef_keyword) >> space >>
            identifier.as(:class_name) >>
            (space >> class_property).repeat(1).as(:class_props) >>
            line_end
        end

        rule(:class_property) do
          (line_end.absent? >> comma.absent? >> any).repeat(1)
        end

        # Class assignment: class target1,target2 className1,className2
        rule(:class_assignment_statement) do
          str('class').as(:class_keyword) >> space >>
            class_assign_targets.as(:class_targets) >> space >>
            class_assign_names.as(:class_names) >>
            line_end
        end

        rule(:class_assign_targets) do
          identifier >> (comma >> identifier).repeat
        end

        rule(:class_assign_names) do
          identifier >> (comma >> identifier).repeat
        end

        # Class shorthand: :::className or :::class1,class2
        rule(:class_shorthand) do
          str(':::') >> class_shorthand_names
        end

        rule(:class_shorthand_names) do
          identifier >> (comma >> identifier).repeat
        end

        # Line terminator
        rule(:line_end) do
          space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end
