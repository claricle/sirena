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
      # accTitle/accDescr text is parsed and discarded: no Diagram::UserJourney
      # attribute holds it yet.
      rule(:accessibility_decl) { acc_descr_block | acc_line }

      # The gap around `:` must stay optional -- mermaid accepts `accDescr : x`.
      # `sp?` here is ASCII-only by design (mermaid's wider `\s` is a known,
      # unclosed gap; see acc_line_space for where the wider set IS required).
      rule(:acc_line) do
        sp? >> (str('accTitle') | str('accDescr')) >> sp? >> str(':') >>
          (nl.absent? >> any).repeat >> (nl | any.absent?)
      end

      rule(:acc_descr_open) { sp? >> str('accDescr') >> sp? >> str('{') }

      # The braced form. The closing brace ends the block; nothing after it on
      # the same line is required -- do not add a line-end requirement here,
      # it re-triggers the quadratic rescan `acc_block_body`'s invariant below
      # exists to prevent (measurements in the gate record).
      rule(:acc_descr_block) do
        acc_descr_open >> acc_block_body >> str('}')
      end

      # INVARIANT: every alternative reachable from `acc_block_comment` must be
      # LINE-BOUNDED (its repeats carry `acc_nl.absent?`, or it consumes a
      # single character). This repeat visits every position in the block, so
      # an alternative able to run to the end of the source makes the whole
      # parse quadratic in the block's length. Anything added to
      # `acc_block_comment` inherits this constraint.
      rule(:acc_block_body) do
        (acc_block_comment | (str('}').absent? >> any)).repeat
      end

      # An opener whose brace never closes makes the whole source unparseable,
      # so `line` (below) must refuse it here rather than let it fall through
      # to `task_line` -- the fallthrough re-scans the rest of the source per
      # line and is quadratic. This deliberately refuses some sources the
      # oracle also refuses, so it never narrows what the grammar accepts.
      rule(:acc_descr_unclosed) { acc_descr_open >> acc_block_body >> any.absent? }

      # Mermaid strips directive lines, then comment lines, before parsing
      # anything, so a `}` inside either must not act as a delimiter here.
      rule(:acc_block_comment) { acc_directive | acc_comment_line }

      # `%%{` opens a DIRECTIVE, not a comment -- `acc_comment_line` must
      # refuse it, or the `}` inside a directive's JSON body could close the
      # accessibility block early (or the directive could swallow the line).
      #
      # The tail `}%%` is REQUIRED here even though mermaid's own directive
      # pattern makes it optional: an optional tail here would leave a block
      # open (and refused) on the same sources the oracle refuses too, so
      # requiring it matches the oracle's verdict via a different mechanism.
      # Known, pinned divergence: mermaid's directive strip isn't anchored to
      # a line start (deletes `%%{x}%%` mid-line); this treats it as text.
      #
      # The body may not cross a line terminator (see the invariant on
      # `acc_block_body`) -- do not make this unbounded, it reintroduces a
      # quadratic scan per `%%{` in a block. This costs a directive split
      # across lines inside a block, which neither this parser nor the oracle
      # accepted before this rule existed either.
      rule(:acc_directive) do
        acc_nl >> acc_line_space.repeat >> str('%%{') >>
          (acc_nl.absent? >> str('}%%').absent? >> any).repeat >> str('}%%')
      end

      rule(:acc_comment_line) do
        acc_nl >> acc_line_space.repeat >> str('%%') >> str('{').absent? >>
          (acc_nl.absent? >> any).repeat
      end

      # `nl` stays LF-only; this rule is wider (ECMAScript's four line
      # terminators) because it alone decides whether a `}` is content or a
      # delimiter -- a narrower set here loses a task in silence (CR/U+2028/
      # U+2029 before `%% }` would close the block and drop it).
      rule(:acc_nl) { match['\n\r\u2028\u2029'] }

      # Mermaid's whitespace set (as flowchart's `line_space` spells it),
      # minus the two terminators `acc_nl` already claims. Only the comment
      # and directive rules use it, because that's the one place a too-narrow
      # set loses content in SILENCE. Do NOT fold this into `acc_nl` -- they
      # must stay disjoint or a run of these chars makes a valid document
      # quadratic (each position reopens the comment rule and backtracks).
      rule(:acc_line_space) do
        match['\t\v\f \u00A0\u1680' \
          '\u2000-\u200A\u202F\u205F\u3000\uFEFF']
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
        title_decl | section_decl | accessibility_decl |
          (acc_descr_unclosed.absent? >> task_line) | comment_line | blank_line
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
        rescue EncodingError => e
          # The accessibility rules' \uXXXX-escaped regexps carry a fixed
          # encoding, so a non-UTF-8 source can reach them and Parslet lets
          # the error escape raw. Catch the whole family, not one subclass --
          # which one raises depends only on which regexp the source hits
          # first. Re-raise as ParseError: that's the contract Base#parse
          # documents.
          raise ParseError, "Parse error: #{e.message}"
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
