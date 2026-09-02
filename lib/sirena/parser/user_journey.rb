# frozen_string_literal: true

require 'parslet'
require_relative 'base'
require_relative '../diagram/user_journey'

module Sirena
  module Parser
    # Parslet grammar for User Journey diagrams
    class UserJourneyGrammar < Parslet::Parser
      rule(:sp) { match('[ \t]').repeat(1) }
      rule(:sp?) { sp.maybe }
      rule(:nl) { str("\n") }

      rule(:journey) { str('journey') >> sp? >> (nl | any.absent?) }
      rule(:title_decl) { sp? >> str('title') >> sp >> text_line.as(:title) >> (nl | any.absent?) }
      rule(:section_decl) do
        sp? >> str('section') >> sp >> text_line.as(:section) >> (nl | any.absent?)
      end
      # mermaid reserves `accTitle` and `accDescr` and puts their text in
      # the SVG's aria attributes. The text is parsed and discarded, since
      # no Diagram::UserJourney attribute holds it yet.
      rule(:accessibility_decl) { acc_descr_block | acc_line }

      # mermaid allows whitespace around the delimiter, so the gap is
      # optional. Demanding the colon immediately after the keyword threw
      # away a whole diagram mmdc renders, and it read `accDescr : 3: Me` as
      # a task named accDescr, where mmdc reads a description and draws no
      # task.
      #
      # `sp?` is ASCII space and tab only, where mermaid's `\s` is wider, so
      # `accTitle` no-break-space `:` is still read as a task here and as a
      # title by mmdc. Closing that needs flowchart's explicit character set
      # (grammars/flowchart.rb:160-175); it is unchanged from before this
      # rule existed, not a regression it introduced.
      rule(:acc_line) do
        sp? >> (str('accTitle') | str('accDescr')) >> sp? >> str(':') >> sp? >>
          (nl.absent? >> any).repeat >> (nl | any.absent?)
      end

      # The braced form, as gantt, pie and timeline spell it. The closing
      # brace is required: mmdc rejects `accDescr {unterminated` in a
      # journey, where in a flowchart it draws the diagram and swallows the
      # rest of the source.
      #
      # Content on the same line AFTER the brace is not handled — mmdc
      # renders `accDescr {Desc}After: 3: Me` as a description plus a task,
      # where this reads the whole line as one task name. That predates this
      # rule (c09c975 produces the identical task) and gantt, pie and
      # timeline share it; flowchart drops the line-end requirement instead.
      rule(:acc_descr_block) do
        sp? >> str('accDescr') >> sp? >> str('{') >>
          (acc_block_comment | (str('}').absent? >> any)).repeat >> str('}') >>
          sp? >> (nl | any.absent?)
      end

      # A standalone `%%` comment line inside the block is consumed whole, so
      # a `}` inside one does not close the block. Without this, the source
      # `accDescr {unterminated` / a task / `%% }` parsed as a diagram with
      # that task silently missing, where both c09c975 and mmdc reject it.
      rule(:acc_block_comment) do
        acc_nl >> line_space.repeat >> str('%%') >>
          (acc_nl.absent? >> any).repeat
      end

      # ECMAScript's four line terminators, which is the set mermaid strips
      # comment lines by. `nl` stays LF-only; this rule is wider because it
      # alone decides whether a `}` is content or a delimiter, and the wrong
      # answer loses a task in silence. Each of CR, U+2028 and U+2029 before
      # `%% }` closed the block and dropped one, where mmdc refuses all three.
      #
      # Nothing else in the grammar reads them, so a wholly CR- or
      # CRLF-delimited journey still fails at the `journey` header exactly as
      # it does at c09c975 — reading those is a new feature, not this repair.
      rule(:acc_nl) { match('[\n\r\u2028\u2029]') }

      # mermaid's explicit whitespace set, copied from grammars/flowchart.rb.
      # Not purely horizontal — it carries U+2028 and U+2029, which acc_nl
      # also treats as line breaks; either reading leaves the comment
      # recognised. Only the comment strip uses it, because that is the one
      # place where
      # too narrow a set loses content in SILENCE: an indent this misses
      # leaves the `}` in `accDescr {...` / `%% }` closing the block and a
      # task disappears. Everywhere else `sp?` staying ASCII only leaves a
      # gap c09c975 has too, where the source is either rejected outright or
      # read as an ordinary task — never quietly shortened.
      rule(:line_space) do
        match['\t\v\f \u00A0\u1680' \
          '\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF']
      end

      rule(:text_line) { (nl.absent? >> str(':').absent? >> any).repeat(1) }
      rule(:task_text) { (str(':').absent? >> nl.absent? >> any).repeat(1) }
      rule(:actor_text) { (match('[,\n]').absent? >> any).repeat(1) }

      rule(:task_line) do
        sp? >>
          task_text.as(:task) >> str(':') >> sp? >>
          match('[0-9]').repeat(1).as(:score) >> str(':') >> sp? >>
          actor_list.as(:actors) >> sp? >> (nl | any.absent?)
      end

      rule(:actor_list) do
        actor_text.as(:actor) >>
          (sp? >> str(',') >> sp? >> actor_text.as(:actor)).repeat
      end

      rule(:line) do
        title_decl | section_decl | accessibility_decl | task_line | comment_line | blank_line
      end
      rule(:comment_line) { sp? >> str('%%') >> (nl.absent? >> any).repeat >> nl }
      rule(:blank_line) { sp? >> nl }

      rule(:journey_doc) do
        journey >>
          line.repeat.as(:lines)
      end

      root(:journey_doc)
    end

    # User Journey diagram parser using Parslet
    class UserJourneyParser < Base
      def parse(source)
        grammar = UserJourneyGrammar.new

        begin
          tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Parse error: #{e.parse_failure_cause.ascii_tree}"
        end

        build_diagram_from_tree(tree)
      end

      private

      def build_diagram_from_tree(tree)
        diagram = Diagram::UserJourney.new
        current_section = nil

        lines = Array(tree[:lines])

        lines.each do |line|
          next unless line.is_a?(Hash)

          if line[:title]
            diagram.title = line[:title].to_s.strip
          elsif line[:section]
            # Save previous section
            diagram.sections << current_section if current_section

            # Create new section
            current_section = Diagram::JourneySection.new
            current_section.name = line[:section].to_s.strip
          elsif line[:task] && current_section
            # Parse task
            task = Diagram::JourneyTask.new
            task.name = line[:task].to_s.strip
            task.score = line[:score].to_s.to_i

            validate_score!(task.score)

            # Extract actors
            actors_data = line[:actors]
            task.actors = if actors_data.is_a?(Array)
                            actors_data.map do |a|
                              a[:actor].to_s.strip
                            end.reject(&:empty?)
                          elsif actors_data.is_a?(Hash) && actors_data[:actor]
                            [actors_data[:actor].to_s.strip]
                          else
                            []
                          end

            current_section.tasks << task
          end
        end

        # Add final section
        diagram.sections << current_section if current_section

        diagram
      end

      def validate_score!(score)
        return if score >= 1 && score <= 5

        raise ParseError, "Score must be between 1 and 5, got #{score}"
      end
    end
  end
end
