# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for State diagrams.
      #
      # Handles State diagram syntax including states, transitions,
      # composite states, special state markers (choice, fork, join),
      # and concurrent states.
      class StateDiagram < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            header_line_direction.absent? >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # A direction is only a direction BELOW the header. Measured against
        # mmdc 11.12.0: `stateDiagram-v2 direction LR` exits 1 and writes no
        # output, while `stateDiagram-v2 A --> B` and a `direction LR` on its
        # own line both render. So the header's line bars the direction
        # statement and nothing else -- other statements stay legal there.
        rule(:header_line_direction) do
          space.repeat >> direction_statement
        end

        # Nothing on the keyword's line is a direction: mmdc 11.12.0 draws
        # `stateDiagram-v2 LR` as a state called LR, not as a left-to-right
        # diagram. Direction is a statement of its own.
        rule(:header) do
          (str('stateDiagram-v2') | str('stateDiagram')).as(:header)
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:spaces) { space.repeat(1) }

        # Keyword forms are listed first for readability, not for
        # correctness: parslet backtracks out of a failed alternative, so
        # `state Foo` still reaches `state_declaration` even when
        # `standalone_state` is tried first — it takes `state` as an id and
        # then fails on the rest of the line. Reordering this list was
        # measured against the suite and changed nothing.
        #
        # What actually keeps `note`, `style`, and `state` from being read as
        # state ids is `reserved_name.absent?`, in `standalone_state` and in
        # `transition_end`. Remove that and the suite goes red.
        rule(:statement) do
          direction_statement |
            style_statement |
            empty_state_statement |
            state_declaration |
            note_block |
            floating_note |
            note_statement |
            transition |
            standalone_state
        end

        # Mermaid lexes a bare `state` as an empty statement. Capturing the
        # keyword lets the transform drop it like any declaration without an
        # id, while `reserved_name` keeps it out of state and transition ids.
        rule(:empty_state_statement) do
          str('state').as(:keyword) >> line_end
        end

        # State declaration with description, marker, or composite body
        rule(:state_declaration) do
          str('state').as(:keyword) >> spaces >>
            (
              marker_declaration |
              state_target >> space? >>
                (
                  state_description |
                  composite_body.as(:composite)
                ).maybe
            ) >>
            line_end
        end

        # Marker declarations do not use the alias syntax. Mermaid takes
        # everything before the marker as its literal id, including quotes and
        # `as`: `state "X" as Y <<choice>>` identifies `"X" as Y`.
        rule(:marker_declaration) do
          marker_state_target.as(:state_id) >> space? >>
            state_marker.as(:marker)
        end

        rule(:marker_state_target) do
          (
            (space? >> state_marker >> line_end).absent? >> line_char
          ).repeat(1)
        end

        # `state "Idle mode" as Idle` names the state Idle and labels it
        # "Idle mode". mmdc 11.12.0 refuses every other shape of this: the
        # reverse order (`state Idle as "Idle mode"`), a single-quoted label
        # and an empty one. It does accept a quoted id after `as`.
        rule(:state_target) do
          (
            str('""').absent? >> state_label_string.as(:state_label) >>
              spaces >> str('as') >> spaces >>
              (quoted_state_id | state_name).as(:state_id)
          ) |
            state_id.as(:state_id)
        end

        # Alias labels do not recognize backslash-escaped quotes. Keep this
        # local: other quoted state syntax has different escape behavior.
        rule(:state_label_string) do
          str('"') >> (str('"').absent? >> any).repeat.as(:string) >> str('"')
        end

        # Unlike ordinary quoted state names, an id declared after `as` keeps
        # its delimiters as part of its identity in Mermaid's StateDB.
        rule(:quoted_state_id) do
          (
            str('"') >>
              (str('\\') >> any | str('"').absent? >> any).repeat >>
              str('"')
          ) |
            (
              str("'") >>
                (str('\\') >> any | str("'").absent? >> any).repeat >>
                str("'")
            )
        end

        # Direction on a line of its own. mmdc 11.12.0 knows TB, BT, LR and
        # RL here and nothing else: `direction TD` draws two states called
        # `direction` and `TD`, which this grammar has no shape for.
        rule(:direction_statement) do
          str('direction') >> spaces >> direction.as(:direction) >> line_end
        end

        rule(:direction) do
          (str('TB') | str('BT') | str('LR') | str('RL')).as(:dir_value)
        end

        # Styling directive, parsed and dropped the way the flowchart
        # grammar treats `style`. mmdc 11.12.0 takes a bare `style A` with
        # no properties at all, so the property list is optional.
        rule(:style_statement) do
          str('style').as(:style_keyword) >> spaces >>
            style_targets.as(:style_targets) >>
            (spaces >> style_properties.as(:style_props)).maybe >>
            line_end
        end

        # Unquoted, and keywords are ordinary names here: mmdc 11.12.0
        # renders `style note fill:red` and refuses `style "A" fill:red`.
        rule(:style_targets) do
          state_name >> (comma >> space? >> state_name).repeat
        end

        # The whole rest of the line, dropped by the transform. Unlike the
        # flowchart's `style`, a `;` splits nothing here: mmdc 11.12.0 draws
        # the same picture for `style A fill:red` and for
        # `style A fill:red;stroke:blue`.
        rule(:style_properties) do
          line_char.repeat(1)
        end

        # Transition between states
        rule(:transition) do
          transition_end.as(:from) >> space? >>
            arrow >>
            space? >>
            transition_end.as(:to) >>
            transition_label.maybe.as(:label) >>
            (
              space? >> arrow >> space? >> transition_end.as(:chain_to)
            ).repeat.as(:chain) >>
            line_end
        end

        # Single-line note. The colon is not optional: once a note names a
        # target and no colon follows, mmdc 11.12.0 is reading a note body
        # and refuses the file if no `end note` closes it.
        rule(:note_statement) do
          note_head >> colon >> space? >> note_text.as(:note_text) >> line_end
        end

        # `note right of X` ... `end note` spans lines. The single-line form
        # cannot swallow the opening line ahead of it, because the colon
        # there is mandatory and a block opener carries none — so the two
        # forms are disjoint and either order parses the same.
        rule(:note_block) do
          note_head >> newline >>
            note_body.as(:note_text) >>
            note_block_end
        end

        rule(:note_head) do
          str('note').as(:note_keyword) >> spaces >>
            note_position.as(:position) >> space >>
            str('of') >> spaces >>
            state_id.as(:note_target) >> space?
        end

        # Everything up to the line that closes the note. An empty body is
        # legal: mmdc 11.12.0 renders `note right of A` / `end note`.
        rule(:note_body) do
          (
            note_block_end.absent? >>
              (newline.absent? >> any).repeat >> newline
          ).repeat
        end

        # `end note` closes the note only when the line ends there. mmdc
        # 11.12.0 keeps `say end notes here` as note text, and keeps a body
        # line ending in `;` or holding a `%%` comment.
        rule(:note_block_end) { space? >> str('end note') >> line_end }

        # A floating note names itself instead of a target. mmdc 11.12.0
        # parses it, draws nothing for it, and takes a non-empty
        # double-quoted text only.
        rule(:floating_note) do
          str('note').as(:note_keyword) >> spaces >>
            str('""').absent? >> quoted_string.as(:note_text) >> spaces >>
            str('as') >> spaces >>
            state_id.as(:note_id) >> line_end
        end

        # A state on a line of its own, with an optional `: description`.
        # mmdc 11.12.0 refuses `note` and `style` in both shapes, the same
        # way it refuses them at a transition end.
        rule(:standalone_state) do
          reserved_name.absent? >> state_id.as(:state_id) >>
            (space? >> bare_state_description).maybe >>
            line_end
        end

        # Either end of a transition. `[*]` is the start or end marker.
        rule(:transition_end) do
          start_end_marker | reserved_name.absent? >> state_id
        end

        # Start/end marker [*]
        rule(:start_end_marker) do
          lbracket >> asterisk >> rbracket
        end

        # State ID (name or quoted string). Keywords are ordinary names
        # here: mmdc 11.12.0 renders `state note` and `state "Label" as
        # note`, and takes `note` as a note's target.
        rule(:state_id) { string | state_name }

        # The three names mmdc 11.12.0 lexes as keywords wherever a statement
        # or a transition end may start: `A --> note`, `note : x`, a bare
        # `style`, and `A --> state` are refused. A bare `state` is an empty
        # statement, while `direction`, `end`, `as`, `notes`, and `styles`
        # all render.
        rule(:reserved_name) do
          (str('note') | str('style') | str('state')) >>
            match['a-zA-Z0-9_'].absent?
        end

        # A bare state name. A superset of `identifier`, which is
        # `[a-zA-Z_][a-zA-Z0-9_]*` and so refuses a leading digit: mmdc
        # 11.12.0 draws `55` as a state called 55.
        rule(:state_name) do
          match['a-zA-Z0-9_'].repeat(1)
        end

        # State description on a `state` statement. The brace is out: it
        # opens the composite body instead.
        rule(:state_description) do
          colon >> space? >>
            (lbrace.absent? >> line_char).repeat(1).as(:description)
        end

        # The bare `id : text` form has no composite body to open, and mmdc
        # 11.12.0 draws a state labelled `text {` for `A : text {` while
        # refusing `state A : text {`.
        rule(:bare_state_description) do
          colon >> space? >>
            (bare_description_end.absent? >> any)
              .repeat(1).as(:description).maybe
        end

        # A bare description treats comments and semicolons as text, ending
        # only at the physical line boundary. Horizontal padding stays outside
        # the captured description.
        rule(:bare_description_end) { space? >> (newline | eof) }

        # One character that is not the end of the line.
        rule(:line_char) { line_end.absent? >> any }

        # State marker: <<choice>>, <<fork>>, <<join>>
        rule(:state_marker) do
          str('<<') >>
            (str('choice') | str('fork') | str('join')).as(:marker_type) >>
            str('>>')
        end

        # Composite state body with nested statements
        rule(:composite_body) do
          lbrace >> ws? >>
            composite_statements.maybe >>
            ws? >> rbrace
        end

        # Statements within composite state
        rule(:composite_statements) do
          (composite_statement >> ws?).repeat(1)
        end

        rule(:composite_statement) do
          concurrent_separator | statement
        end

        # Concurrent state separator
        rule(:concurrent_separator) do
          str('--').as(:concurrent_sep) >> line_end
        end

        # Arrow for transitions
        rule(:arrow) do
          str('-->').as(:arrow)
        end

        # Transition label (after colon)
        rule(:transition_label) do
          space? >> colon >> space? >>
            (arrow.absent? >> line_char).repeat(1).as(:label_text)
        end

        # Note position
        rule(:note_position) do
          str('left') | str('right')
        end

        # Note text
        rule(:note_text) { line_char.repeat(1) }

        # Line terminators for State diagrams
        rule(:line_end) do
          semicolon.maybe >> space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end
