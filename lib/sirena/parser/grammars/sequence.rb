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
          str('sequenceDiagram').as(:header) >> ws?
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

        # An actor name is a bounded run of text, not a programming
        # identifier: mermaid accepts spaces, parentheses, dashes, `=` and
        # a leading digit (`Alice ()`, `Alice-in-Wonderland`, `1`).
        #
        # `actor_stop` names every boundary an actor name yields to. It
        # includes `arrow_base` rather than `arrow` because the activation
        # suffix is `.maybe`, so the two are equivalent as a boundary and
        # `arrow_base` says what is meant. `%%` is required even though a
        # bare `%` stays name material: `line_end` lets every statement
        # carry a trailing comment, so an actor name has to yield to `%%`
        # or `participant Alice %% who` would swallow the comment into the
        # id. `alias_keyword` needs surrounding whitespace so it splits
        # `participant 1 as text` at the keyword without eating a name like
        # `Cast Away` (`t A` is not ` as `). `@{` (never a bare `@`) is the
        # shape-metadata opener.
        rule(:alias_keyword) { space.repeat(1) >> str('as') >> space.repeat(1) }

        rule(:actor_stop) do
          arrow_base | colon | comma | semicolon | str('%%') |
            alias_keyword | str('@{') | newline
        end

        # `+` and `<` are never `actor_name` material (used by note/activate/
        # deactivate references) — they would collide with the activation
        # suffix (`A->>+B`) or an arrow spelling (`<<->>`). This does NOT
        # generalise to a `participant`/`actor` DECLARATION: a declaration
        # has no arrow to collide with, and mermaid accepts `participant
        # A+B` outright (id "A+B") — see `declaration_stop` below, which
        # bans `<>` but deliberately not `+`. Measured against mermaid
        # 11.16.1's own parser directly; a stale version of this comment
        # once claimed `participant A+B` was rejected too.
        #
        # A dash is consumed unless the very next thing is another dash or
        # the start of a genuine arrow — that is the only real ambiguity a
        # trailing dash creates (`A--->B` must not read as actor `A-` plus
        # arrow `-->`). `newline` is deliberately absent from this set,
        # unlike the general `actor_stop` gate above: a trailing dash at
        # end-of-statement is exactly as legal as one at end-of-file (both
        # already work — `participant A-` at EOF gives `"A-"`), and mmdc
        # accepts `participant A-` followed by more statements the same
        # way. The general gate still stops an ordinary character at a
        # newline, so a name still cannot span multiple lines.
        rule(:actor_char) do
          actor_stop.absent? >>
            (match['^+<-'] |
              (str('-') >>
                (str('-') | arrow_base | colon | comma | semicolon |
                  str('%%') | alias_keyword | str('@{')).absent?))
        end

        # An arrow-tail character cannot open a name: `A->)B` is a bad
        # arrow, not a message into an actor called `)B`. `/` joins the
        # same set — it opens three reversed-arrow spellings (`/|-`,
        # `/|--`, `//-`, `//--`), so `A->>/B` is a bad arrow rather than a
        # message to `/B`; measured, mermaid rejects it there while
        # accepting `/` elsewhere in a name.
        rule(:actor_lead) { match[')|>/'].absent? >> actor_char }

        rule(:actor_name) { actor_lead >> actor_char.repeat }

        # `actor_name` above is shared by every OTHER actor reference
        # (notes, activate/deactivate) and stays untouched. Declarations
        # and message endpoints get their own rules below: mermaid's real
        # grammar treats the two very differently, and forcing one token
        # to cover both is what created phantom actors and rejected valid
        # input in three places at once (measured against mermaid
        # 11.16.1's own parser and lexer directly).
        #
        # A declaration has no arrow next to it, so there is nothing for
        # a `+`, a `-` run, or a leading `/` to be ambiguous with —
        # `actor_char`'s bans on those exist only to protect a message's
        # arrow and activation-suffix syntax. Measured: `participant
        # A+B`, `participant /B`, `participant )B`, `participant |B` and
        # `participant A--B` all succeed with those literal ids; only `<`
        # and `>` are ever rejected.
        # Bare `@` is banned outright, not just the `@{` shape-metadata
        # opener — measured against mermaid 11.16.1: `participant A@B`
        # raises `Expecting 'ACTOR', got 'INVALID'`. Banning only `@{`
        # left a bare `@` as ordinary id material, which mermaid never
        # accepts (`shape_metadata` below still matches `@{...}` right
        # after this stop point when metadata is actually present).
        rule(:declaration_stop) do
          match['<>'] | colon | comma | semicolon | str('%%') |
            str('@') | newline
        end

        rule(:declaration_char) { declaration_stop.absent? >> any }

        # The `as`-alias split only fires when the id BEFORE it has no
        # embedded whitespace — mermaid's own ID-then-AS lexer rule
        # (`[^<>:\n,;@\s]+(?=\s+as\s)`) excludes whitespace from that id
        # entirely. When the id DOES contain whitespace, `as` is not a
        # keyword boundary and the whole thing — "as" included — stays one
        # id. Measured against mermaid 11.16.1 directly:
        #   `participant A as C`     -> id "A", label "C" (alias applies)
        #   `participant A B as C`   -> id "A B as C", no label at all
        # `declaration_word_char` is deliberately narrower than
        # `declaration_char` (it also excludes whitespace) so the
        # lookahead below only fires on a whitespace-free run, exactly
        # matching that lexer rule.
        rule(:declaration_word_char) do
          (declaration_stop | space).absent? >> any
        end

        rule(:declaration_name) do
          (declaration_word_char.repeat(1) >> alias_keyword.present?) |
            declaration_char.repeat(1)
        end

        # A message endpoint sits next to an arrow, so it keeps
        # `actor_char`'s arrow-safety, but two of its restrictions are
        # wrong for a message specifically:
        #
        # - `alias_keyword` must NOT stop a message name. Measured: `A as
        #   Z->>B: m` and `A->>B as Z: m` both parse in mermaid with `as`
        #   as ordinary text — ` as ` only splits id from label inside a
        #   `participant`/`actor` statement, never inside a message.
        # - `(` and `)` must stop a message name instead of joining it.
        #   Unlike a declaration's literal `Alice ()`, a `()` touching a
        #   message endpoint is mermaid's own central-connection
        #   decoration (jison terminal `()`, `LINETYPE.CENTRAL_CONNECTION`
        #   /`_REVERSE`/`_DUAL`) and never becomes part of the actor's
        #   identity: `A ()->>B: m` and `A->>() B: m` both resolve to the
        #   two declared actors `A`/`B`, not to phantom actors `A ()` /
        #   `() B`.
        rule(:message_actor_stop) do
          arrow_base | colon | comma | semicolon | str('%%') |
            str('@{') | lparen | rparen | newline
        end

        # A trailing dash fuses with `()` into the actor's OWN identity
        # instead of being read as the central-connection decoration —
        # measured against mermaid 11.16.1's own ACTOR lexer regex
        # directly (`[^\/\\+()+<->:\n,;]+((?!(...|\(\)))[\-]*[^+<->:\n,;]+)*`):
        # a `()` that follows a dash is swallowed by the same continuation
        # branch that swallows the dash, so it is never offered to the
        # bare-`()` central-connection alternative at all.
        #   `A ()->>B: m`   -> actors "A", "B"        (no dash before `()`)
        #   `A- ()->>B: m`  -> actor  "A- ()"          (dash fuses it in)
        #   `A-()->>B: m`   -> actor  "A-()"           (no space needed)
        # Tried before the plain dash branch below, since Parslet
        # alternation is first-match and this is the more specific case.
        rule(:message_actor_paren_unit) do
          str('-') >> space.repeat >> central_connection
        end

        rule(:message_actor_char) do
          message_actor_stop.absent? >>
            (message_actor_paren_unit |
              match['^+<>()-'] |
              (str('-') >> (str('-') | message_actor_stop).absent?))
        end

        # `>` joins `<` as never message-actor material, in any position —
        # not just leading. Measured: `A->>B>C: m` raises on mermaid
        # (`got 'INVALID'`); base only excluded `>` from the immediate
        # arrow-tail set below, not from `message_actor_char`, so it kept
        # reading past an interior `>` and merged `B>C` into one actor.
        #
        # `\` joins the arrow-tail set for the same reason `/` is already
        # there: a name cannot OPEN with it, because it also opens the
        # reversed-arrow spellings (`\|-`, `\|--`, `\\-`, `\\--`).
        # Measured: `A->>\B: m` raises on mermaid (`got 'INVALID'`); base
        # accepted it and rendered actor `"\\B"`.
        rule(:message_actor_lead) do
          match[')|>/\\\\'].absent? >> message_actor_char
        end

        rule(:message_actor_name) do
          message_actor_lead >> message_actor_char.repeat
        end

        # The decoration is parsed and discarded, not modeled — Sirena
        # does not draw the central-connection marker, so only the
        # phantom-actor bug needs closing here. No embedded whitespace
        # rule of its own: the message rule wraps it in `space?` on both
        # sides, matching jison's `()` token lexing in the
        # whitespace-skipping INITIAL state (`A()->>B` and `A ()->>B`
        # are both legal).
        rule(:central_connection) { str('()') }

        # Shape metadata (`@{"type":"boundary"}`) is parsed and discarded,
        # not validated as JSON — a nested `{...}` on one line still ends
        # the payload at its first `}` (no corpus case has one). Bounded
        # to one line — `newline.absent?` is load-bearing, not tidiness:
        # an unclosed `@{` would otherwise scan into a later statement's
        # closing brace and silently discard everything between, rather
        # than raising. `repeat(1)`, not `repeat`: mermaid rejects an
        # empty `@{}`, so the payload must not be empty either.
        rule(:shape_metadata) do
          str('@{') >>
            (str('}').absent? >> newline.absent? >> any).repeat(1) >>
            str('}')
        end

        # Participant declarations
        rule(:participant_declaration) do
          str('participant') >> space.repeat(1) >>
            declaration_name.as(:id) >> shape_metadata.maybe >> space? >>
            (str('as') >> space.repeat(1) >> label.as(:label)).maybe >>
            line_end.as(:participant)
        end

        rule(:actor_declaration) do
          str('actor') >> space.repeat(1) >>
            declaration_name.as(:id) >> shape_metadata.maybe >> space? >>
            (str('as') >> space.repeat(1) >> label.as(:label)).maybe >>
            line_end.as(:actor)
        end

        # Messages with arrows (order matters: longest patterns first)
        rule(:message) do
          message_actor_name.as(:from) >> space? >>
            message_signal.as(:arrow) >> space? >>
            message_actor_name.as(:to) >> space? >>
            message_text.maybe.as(:text) >>
            line_end
        end

        # A central-connection decoration and an activation suffix never
        # coexist on the same message — measured against mermaid 11.16.1
        # directly: `A->>+()B`, `A->>()+B`, `A()->>+B`, `A<<->>+()B` and
        # `A<<->>()+B` all raise ("Expecting 'ACTOR'"/"'+'"/"'-'"),
        # whichever side carries the decoration and whichever carries the
        # suffix. `A-()->>+B` only looks like a counterexample: there the
        # `()` is fused into the FROM actor's own identity by
        # `message_actor_paren_unit` above, so no real central connection
        # reaches this rule at all, and the plain third branch below
        # applies instead.
        #
        # A branch with `()` present therefore uses `arrow_base` alone —
        # no `activation_suffix` component exists to try. Parslet
        # alternation is first-match, so the connection branches are tried
        # before the plain one; `central_connection` stays uncaptured
        # here, same as before this rule existed — it is parsed and
        # discarded either way.
        rule(:message_signal) do
          (central_connection >> space? >> arrow_base.as(:arrow_base) >>
            space? >> central_connection.maybe) |
            (arrow_base.as(:arrow_base) >> space? >> central_connection) |
            arrow
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
            (line_end.absent? >> any).repeat.as(:message_text)
        end

        # Notes
        rule(:note_statement) do
          (str('note') | str('Note')) >> space.repeat(1) >>
            note_position.as(:position) >> space.repeat(1) >>
            note_participants.as(:participants) >> space? >>
            colon >> space? >>
            (line_end.absent? >> any).repeat.as(:note_text) >>
            line_end
        end

        rule(:note_position) do
          (str('left') >> space.repeat(1) >> str('of')).as(:left_of) |
            (str('right') >> space.repeat(1) >> str('of')).as(:right_of) |
            str('over').as(:over)
        end

        rule(:note_participants) do
          actor_name.as(:participant) >>
            (space? >> comma >> space? >>
             actor_name.as(:participant)).repeat
        end

        # Activation/Deactivation commands. Widened to `actor_name` for
        # construct completeness: an actor name is one construct, and
        # leaving these two sites on `identifier` would make
        # `participant 1` parse while `activate 1` failed on the very same
        # actor.
        rule(:activation_command) do
          str('activate') >> space.repeat(1) >>
            actor_name.as(:activate) >>
            line_end
        end

        rule(:deactivation_command) do
          str('deactivate') >> space.repeat(1) >>
            actor_name.as(:deactivate) >>
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

        rule(:alt_structure) do
          str('alt') >> space? >>
            (line_end.absent? >> any).repeat.as(:alt_label) >>
            line_end >>
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

        rule(:par_structure) do
          str('par') >> space? >>
            (line_end.absent? >> any).repeat.as(:par_label) >>
            line_end >>
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