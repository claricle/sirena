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
      #
      # "The oracle" throughout these rules means mermaid 11.16.1 driven by
      # mermaid-cli 11.12.0; the spec carries the command that reproduces
      # every verdict quoted here.
      rule(:accessibility_decl) { acc_descr_block | acc_line }

      # mermaid allows whitespace around the delimiter, so the gap is
      # optional. Demanding the colon immediately after the keyword threw
      # away a whole diagram the oracle renders, and it read `accDescr : 3:
      # Me` as a task named accDescr, where the oracle reads a description
      # and draws no task.
      #
      # `sp?` is ASCII space and tab only, where mermaid's `\s` is wider, so
      # `accTitle` no-break-space `:` is still read as a task here and as a
      # title by the oracle. Closing that needs flowchart's `line_space`
      # character set; it is unchanged from before this rule existed, not a
      # regression it introduced.
      rule(:acc_line) do
        sp? >> (str('accTitle') | str('accDescr')) >> sp? >> str(':') >>
          (nl.absent? >> any).repeat >> (nl | any.absent?)
      end

      rule(:acc_descr_open) { sp? >> str('accDescr') >> sp? >> str('{') }

      # The braced form, as gantt, pie and timeline spell it. The closing
      # brace is required: the oracle rejects `accDescr {unterminated` in a
      # journey, where in a flowchart it draws the diagram and swallows the
      # rest of the source.
      #
      # Content on the same line AFTER the brace is not handled — the oracle
      # renders `accDescr {Desc}After: 3: Me` as a description plus a task,
      # where this rule declines the line, `task_line` claims it, and the
      # whole of `accDescr {Desc}After` becomes one task name scoring 3 for
      # Me. That predates this rule (the parser before this change produces
      # the identical task) and gantt, pie and timeline share it; flowchart
      # drops the line-end requirement instead.
      rule(:acc_descr_block) do
        acc_descr_open >> acc_block_body >> str('}') >> sp? >> (nl | any.absent?)
      end

      rule(:acc_block_body) do
        (acc_block_comment | (str('}').absent? >> any)).repeat
      end

      # An opener whose brace never closes makes the whole source
      # unparseable, so `line` refuses it here instead of letting it fall
      # through to `task_line`. The fallthrough was quadratic: a task-shaped
      # opener such as `accDescr {x: 3: Me` still succeeded as a task, so
      # every later line paid for its own scan to the end of the source. 4000
      # of them took 188s and 1 GB of RSS, against 0.7s and 167 MB for the
      # same input before the braced form existed. Refusing the line runs the
      # scan at most twice and only on the line that fails.
      #
      # It refuses no source the grammar accepted before: reaching this rule
      # already means the block did not close, and the oracle rejects an
      # unclosed block in a journey whatever follows the brace.
      rule(:acc_descr_unclosed) { acc_descr_open >> acc_block_body >> any.absent? }

      # Mermaid deletes directive lines and then comment lines before it
      # parses anything, so a `}` inside either is not a delimiter. Without
      # this, the source `accDescr {unterminated` / a task / `%% }` parsed as
      # a diagram with that task silently missing, where both the oracle and
      # the parser before this change reject it.
      #
      # Mermaid runs the two strips as two separate passes, directives first
      # (`removeDirectives`, then `cleanupComments`). This is one alternation
      # rather than two passes, so it is not the same algorithm; it is only
      # measured to give the same answer on the shapes the specs cover.
      rule(:acc_block_comment) { acc_directive | acc_comment_line }

      # `%%{` opens a DIRECTIVE, not a comment, which is why
      # `acc_comment_line` must refuse it. Reading
      # `%%{init: {"theme":"dark"}}%%` as a comment swallowed the line whole
      # and let a later `}` close the block; reading it as ordinary text let
      # the `}` inside the JSON close the block early. Both disagree with the
      # oracle, in opposite directions, so the directive gets its own rule.
      #
      # The tail `}%%` is REQUIRED here where mermaid's own directive pattern
      # makes it optional and runs to the end of the source without it. The
      # two still agree on `%%{init: {...}}`: the oracle rejects it because
      # the unterminated directive eats the rest of the source and leaves
      # `accDescr {` open, and this rejects it because the line falls through
      # to the character branch and the `}` inside the JSON closes the block
      # early. Same verdict, different mechanism.
      #
      # Two divergences from mermaid are known and left standing, both
      # pinned by examples. Mermaid's directive strip is NOT anchored to a
      # line start, so it deletes `%%{x}%%` from mid-line where this refuses
      # the source. And where a directive has no tail, mermaid swallows the
      # rest of the source and still renders, where making the tail optional
      # here would leave the block open and refuse it — so requiring the
      # tail is the reading that agrees with the oracle's answer, even
      # though the optional tail is the more faithful pattern.
      rule(:acc_directive) do
        acc_nl >> acc_line_space.repeat >> str('%%{') >>
          (str('}%%').absent? >> any).repeat >> str('}%%')
      end

      rule(:acc_comment_line) do
        acc_nl >> acc_line_space.repeat >> str('%%') >> str('{').absent? >>
          (acc_nl.absent? >> any).repeat
      end

      # `nl` stays LF-only; this rule is wider because it alone decides
      # whether a `}` is content or a delimiter, and the wrong answer loses a
      # task in silence. Each of CR, U+2028 and U+2029 before `%% }` closed
      # the block and dropped one, where the oracle refuses all three.
      #
      # These are ECMAScript's four line terminators, and mermaid does anchor
      # its comment strip after all four. Its comment BODY is `[^LF]+`
      # though, so mermaid ends a comment at a line feed alone where this
      # rule ends one at any of the four. The reachable consequence is
      # `accDescr {` / `%% x` U+2028 `}`, which the oracle renders and this
      # parser refuses. A refusal is a visible answer rather than a quietly
      # wrong picture, so it is left as it is.
      #
      # Nothing else in the grammar reads them, so a wholly CR- or
      # CRLF-delimited journey still fails at the `journey` header exactly as
      # it did before this change — reading those is a new feature, not this
      # repair.
      rule(:acc_nl) { match['\n\r\u2028\u2029'] }

      # Mermaid's explicit whitespace set, as flowchart's `line_space` spells
      # it, minus the two terminators `acc_nl` already claims. Only the
      # comment and directive rules use it, because that is the one place
      # where too narrow a set loses content in SILENCE: an indent this
      # misses leaves the `}` in `accDescr {...` / `%% }` closing the block
      # and a task disappears. Everywhere else `sp?` staying ASCII only
      # leaves a gap the parser had before this change too, where the source
      # is either rejected outright or read as an ordinary task — never
      # quietly shortened.
      #
      # Dropping U+2028 and U+2029 narrows nothing in effect: a run of them
      # is still a run of `acc_nl`, and the comment opens at the last one, so
      # the same sources are recognised. Sharing them with `acc_nl` made a
      # VALID document quadratic instead — at every U+2028 the comment rule
      # opened, this repeat ate the whole remaining run, the `%%` failed and
      # all of it backtracked to consume one character. A 9 KB block of them
      # took 0.923s against 0.029s for the same block of no-break spaces, and
      # the ratio grew with the block.
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
          # The accessibility rules are the only regexps in this grammar that
          # carry a fixed encoding — a `\uXXXX` escape sets one even though
          # every character in the set is ASCII — so a source that is valid
          # in a non-UTF-8 encoding reaches them and Parslet lets the error
          # out. Parser::Base#parse documents ParseError, which is what the
          # parser raised on these sources before the braced form existed.
          # The whole EncodingError family is caught rather than the one
          # subclass measured escaping, because they differ only in which
          # regexp the source happens to reach first.
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
