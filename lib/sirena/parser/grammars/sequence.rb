# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for sequence diagrams.
      #
      # Handles all sequence diagram syntax including participants, messages,
      # notes, activations, and control structures. The grammar properly handles
      # complex arrow patterns with activation modifiers that cannot be parsed
      # correctly by regex-based lexers.
      class Sequence < Common
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
          str('sequenceDiagram').as(:header) >> semicolon.maybe >> ws?
        end

        # mmdc treats a bare `;` as a statement separator, equivalent to a
        # newline (`A->>B: hi;C->>D: bye` parses as two statements, same as
        # one per line). common.rb's `line_end` only accepts `;` immediately
        # before a real newline/eof, so it never fires as a mid-line
        # separator — and it is NOT overridden wholesale here, because
        # `line_end` also gates every *_label free-text capture below
        # (alt/par/loop/opt/critical/box), and those labels can legitimately
        # CONTAIN a literal `;` as plain text (spec/mermaid/sequence/
        # 049_parser_should_handle_special_characters_in_alt_48.mmd, already
        # passing — widening `line_end` itself would truncate it instead of
        # treating it as a separator).
        #
        # A bare `;` counts as a separator only when a real statement (or
        # eof) follows it — checked with a lookahead, not merely "is there a
        # semicolon here". Without that guard, note/message text containing
        # a literal `;` that ISN'T a separator (spec/mermaid/sequence/
        # 046_parser_should_handle_special_characters_in_notes_45.mmd: note
        # text "-:<>,;# comment", where "# comment" is not a statement)
        # would be truncated and leave unparseable trailing text, turning a
        # currently-passing case into a hard parse failure. Used only where
        # a `;` genuinely closes a statement: message and note text, and
        # their trailing terminators.
        rule(:statement_separator) do
          (semicolon >> (statement.present? | eof)) | line_end
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          participant_declaration |
            actor_declaration |
            note_statement |
            box_statement |
            activation_command |
            deactivation_command |
            control_structure |
            message
        end

        # Participant declarations
        rule(:participant_declaration) do
          str('participant') >> space.repeat(1) >>
            identifier.as(:id) >> space? >>
            (str('as') >> space.repeat(1) >> label.as(:label)).maybe >>
            line_end.as(:participant)
        end

        rule(:actor_declaration) do
          str('actor') >> space.repeat(1) >>
            identifier.as(:id) >> space? >>
            (str('as') >> space.repeat(1) >> label.as(:label)).maybe >>
            line_end.as(:actor)
        end

        # Messages with arrows (order matters: longest patterns first)
        rule(:message) do
          identifier.as(:from) >> space? >>
            arrow.as(:arrow) >> space? >>
            identifier.as(:to) >> space? >>
            message_text.maybe.as(:text) >>
            statement_separator
        end

        # Arrow types including activation modifiers
        # Critical: These must be tried in order from longest to shortest
        rule(:arrow) do
          arrow_base.as(:arrow_base) >> activation_suffix.maybe.as(:activation)
        end

        # Every spelling mmdc 11.12.0 renders, and only those. Half and
        # stick heads come in a reversed spelling too, which puts the marker
        # on the source end: `A//-B` and `A-//B` draw the same head at
        # opposite ends of the line.
        #
        # `->|` and `-->|` are NOT arrows. mmdc reads `A->|B` as `->` into
        # an actor named `|B`, so treating the pipe as part of the arrow
        # named the wrong participant.
        #
        # Parslet alternation is first-match, so a genuine prefix pair has
        # to be listed longest-first: `-->` before `-->>` would swallow it,
        # and so would `//-` before `//--`. Nothing else here shadows —
        # no solid arrow's second character is a dash, so the families are
        # order-independent between themselves.
        rule(:arrow_base) do
          str('<<-->>') | str('<<->>') |
            dotted_arrow | solid_arrow | reversed_arrow
        end

        rule(:dotted_arrow) do
          str('-->>') | str('--|/') | str('--|\\') | str('--//') |
            str('--\\\\') | str('--x') | str('--X') | str('--)') | str('-->')
        end

        rule(:solid_arrow) do
          str('->>') | str('-|/') | str('-|\\') | str('-//') |
            str('-\\\\') | str('-x') | str('-X') | str('-)') | str('->')
        end

        rule(:reversed_arrow) do
          str('/|--') | str('/|-') | str('\\|--') | str('\\|-') |
            str('//--') | str('//-') | str('\\\\--') | str('\\\\-')
        end

        rule(:activation_suffix) { space? >> match['+-'] }

        rule(:message_text) do
          colon >> space? >>
            (html_entity | (statement_separator.absent? >> any)).repeat.as(:message_text)
        end

        # `#9829;` (mmdc: renders "♥") is an HTML numeric/named entity, not a
        # statement separator — its `;` must not trigger statement_separator.
        # Matched as one atomic token so message_text's stop-check never
        # evaluates the entity's own semicolon in isolation.
        rule(:html_entity) do
          hash >> match['a-zA-Z0-9'].repeat(1) >> semicolon
        end

        # Notes
        rule(:note_statement) do
          (str('note') | str('Note')) >> space.repeat(1) >>
            note_position.as(:position) >> space.repeat(1) >>
            note_participants.as(:participants) >> space? >>
            colon >> space? >>
            (statement_separator.absent? >> any).repeat.as(:note_text) >>
            statement_separator
        end

        rule(:note_position) do
          (str('left') >> space.repeat(1) >> str('of')).as(:left_of) |
            (str('right') >> space.repeat(1) >> str('of')).as(:right_of) |
            str('over').as(:over)
        end

        rule(:note_participants) do
          identifier.as(:participant) >>
            (space? >> comma >> space? >>
             identifier.as(:participant)).repeat
        end

        # Activation/Deactivation commands
        rule(:activation_command) do
          str('activate') >> space.repeat(1) >>
            identifier.as(:activate) >>
            line_end
        end

        rule(:deactivation_command) do
          str('deactivate') >> space.repeat(1) >>
            identifier.as(:deactivate) >>
            line_end
        end

        # Box grouping
        rule(:box_statement) do
          str('box') >> space.repeat(1) >>
            (line_end.absent? >> any).repeat.as(:box_label) >>
            line_end >>
            ws? >>
            statements.as(:box_statements) >>
            ws? >>
            str('end') >> line_end
        end

        # Control structures
        rule(:control_structure) do
          loop_structure |
            alt_structure |
            opt_structure |
            par_structure |
            critical_structure |
            break_structure
        end

        rule(:loop_structure) do
          str('loop') >> space? >>
            (line_end.absent? >> any).repeat.as(:loop_label) >>
            line_end >>
            ws? >>
            statements.as(:loop_statements) >>
            ws? >>
            str('end') >> line_end
        end

        # `alt;Bob-->Alice: ...` (mmdc: an alt block with NO label, `;` in
        # place of the newline it would otherwise take). The first branch
        # only fires when `;` is the very next character — a `;` embedded
        # later in real label text (case 049 above) never reaches it, and
        # falls through to the second branch unchanged.
        rule(:alt_structure) do
          str('alt') >> space? >>
            (
              (semicolon >> str('').as(:alt_label)) |
              ((line_end.absent? >> any).repeat.as(:alt_label) >> line_end)
            ) >>
            ws? >>
            statements.as(:alt_statements) >>
            ws? >>
            (
              str('else') >> space? >>
              (line_end.absent? >> any).repeat.as(:else_label) >>
              line_end >>
              ws? >>
              statements.as(:else_statements) >>
              ws?
            ).repeat.as(:else_blocks) >>
            str('end') >> line_end
        end

        rule(:opt_structure) do
          str('opt') >> space? >>
            (line_end.absent? >> any).repeat.as(:opt_label) >>
            line_end >>
            ws? >>
            statements.as(:opt_statements) >>
            ws? >>
            str('end') >> line_end
        end

        # Same no-label bare-`;` shape as alt_structure above.
        rule(:par_structure) do
          str('par') >> space? >>
            (
              (semicolon >> str('').as(:par_label)) |
              ((line_end.absent? >> any).repeat.as(:par_label) >> line_end)
            ) >>
            ws? >>
            statements.as(:par_statements) >>
            ws? >>
            (
              str('and') >> space? >>
              (line_end.absent? >> any).repeat.as(:and_label) >>
              line_end >>
              ws? >>
              statements.as(:and_statements) >>
              ws?
            ).repeat.as(:and_blocks) >>
            str('end') >> line_end
        end

        rule(:critical_structure) do
          str('critical') >> space? >>
            (line_end.absent? >> any).repeat.as(:critical_label) >>
            line_end >>
            ws? >>
            statements.as(:critical_statements) >>
            ws? >>
            (
              str('option') >> space? >>
              (line_end.absent? >> any).repeat.as(:option_label) >>
              line_end >>
              ws? >>
              statements.as(:option_statements) >>
              ws?
            ).repeat.as(:option_blocks) >>
            str('end') >> line_end
        end

        rule(:break_structure) do
          str('break') >> space? >>
            (line_end.absent? >> any).repeat.as(:break_label) >>
            line_end >>
            ws? >>
            statements.as(:break_statements) >>
            ws? >>
            str('end') >> line_end
        end

        # Label can be quoted or unquoted text
        rule(:label) do
          string | unquoted_label
        end

        rule(:unquoted_label) do
          (line_end.absent? >> any).repeat(1)
        end
      end
    end
  end
end