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

        # A `;`-terminated statement can be followed by another bare `;`
        # with nothing between them (`m;;m2`): the first `;` already ends
        # the statement via `content_boundary`, and mermaid treats the
        # second as an empty no-op statement rather than a syntax error
        # (measured against mermaid 11.16.1: `Alice->>Bob: m;;Alice->>Bob:
        # m2` gives 2 messages). Without this, `statements`' `repeat(1)`
        # has nowhere to put that second `;` — no rule in `statement`
        # starts on one — and the whole diagram fails to parse. Swallowing
        # any run of extra `;`s after each statement mirrors that, the
        # same way `ws?` already swallows blank space between statements.
        rule(:statements) do
          (statement >> ws? >> (semicolon >> ws?).repeat).repeat(1)
        end

        rule(:statement) do
          comment_statement |
            hash_comment_statement |
            metadata_statement |
            create_statement |
            destroy_statement |
            links_statement |
            participant_declaration |
            actor_declaration |
            note_statement |
            box_statement |
            activation_command |
            deactivation_command |
            control_structure |
            message
        end

        # A line starting with a bare `%` (not opening `%{`) is a whole-line
        # comment to mermaid, contributing zero statements — mermaid's own
        # comment rule takes priority over its actor rule at the start of a
        # statement, so a leading `%` swallows the rest of the line whatever
        # punctuation follows it. `message_actor_lead` already refuses to let
        # a message actor START with a bare `%` (`mermaid_token_opener`,
        # below), so it agrees such a line is never a message — but until
        # this rule it had no statement to fall back to, so the whole
        # diagram failed instead of skipping one line.
        #
        # No `.as(...)` in this rule. `root` is `diagram`, which always pairs
        # `statements` with `header.as(:header)`, and Parslet drops an
        # unnamed match when composing it alongside a named one rather than
        # handing it up as an array entry — verified by parsing the real
        # `diagram` root, not this rule in isolation (calling `statements`
        # directly returns a bare `Parslet::Slice`, a code path the parser
        # never actually takes): `g.parse("sequenceDiagram\n%c\nA->>B: m\n")`
        # comes back `[{header: ...}, {from: "A", ...}]`, two entries, not
        # three — the comment line leaves nothing behind for
        # `Builders::Sequence`'s `is_a?(Hash)` guards in
        # `apply`/`process_statements` to skip. Those guards are real and
        # matter for other rules; they simply never see this one.
        #
        # A comment line does not swallow the statement after it
        # (`%c\nA->>B: m\n` still yields participants `A`, `B`). A line
        # starting `%%` also parses to zero participants, matching mermaid,
        # but NOT through this rule — `diagram`'s own `ws?` right after
        # `header` already consumes it via `common.rb`'s `comment` rule
        # (`%%` to end of line) before `statements` ever gets a chance to
        # try this one. Do not read that case as evidence for this rule.
        rule(:comment_statement) do
          str('%') >> str('{').absent? >>
            (line_end.absent? >> any).repeat >> line_end
        end

        # `title`, `accTitle`, `accDescr` and `autonumber` are recognised so
        # the diagram parses, and contribute no statement: like
        # `comment_statement`, no `.as(...)`. The title, accessibility text
        # and message numbering are not drawn. Each rule must end at
        # `line_end` or `content_boundary` (which also accepts `;`), which
        # keeps `autonumber->>B: m` and `title->>B: m` ordinary messages.
        rule(:metadata_statement) do
          title_statement | acc_title_statement | acc_descr_block |
            acc_descr_statement | autonumber_statement
        end

        rule(:title_statement) do
          str('title') >> (colon >> space? | space.repeat(1)) >>
            match['^#;\n'].repeat >> content_boundary
        end

        rule(:acc_title_statement) do
          str('accTitle') >> space? >> colon >> rest_of_line
        end

        rule(:acc_descr_statement) do
          str('accDescr') >> space? >> colon >> rest_of_line
        end

        rule(:acc_descr_block) do
          str('accDescr') >> space? >> lbrace >>
            (rbrace.absent? >> any).repeat >> rbrace >> content_boundary
        end

        rule(:autonumber_statement) do
          str('autonumber') >>
            (space.repeat(1) >> (str('off') | numbering)).maybe >> content_boundary
        end

        # mermaid's NUM: digits with up to two decimals, or a leading-dot decimal.
        rule(:number) do
          (match['0-9'].repeat(1) >> (str('.') >> match['0-9'].repeat(1, 2)).maybe) |
            (str('.') >> match['0-9'].repeat(1, 2))
        end

        rule(:numbering) do
          number >> (space.repeat(1) >> number).maybe
        end

        # A `#` comment runs to the physical line end, `;` included —
        # shared by every `content_boundary` caller below.
        rule(:trailing_comment) do
          (space? >> str('#') >> match['^\n'].repeat).maybe
        end

        # The boundary a `;`-aware text capture (`text_run` below) yields
        # to: an optional trailing `#` comment, then a line end or an
        # inline `;`. The bare `\r` + eof arm exists because `text_run`
        # stops at every `\r`; only direct `Parser::Sequence#parse` calls
        # reach it, since `Source#normalize` rewrites `\r\n?` first.
        rule(:content_boundary) do
          trailing_comment >> (line_end | semicolon | (str("\r") >> eof))
        end

        # A whole-line `#...` comment left behind once a label capture
        # stops at an inline `;` (`alt -:<>,;# comment` splits into a
        # label ending at the `;` and this bare comment line — only
        # `alt`/`par` opening labels are `;`-aware; `loop`'s is not).
        # Mirrors `comment_statement` above: no `.as(...)`, contributes
        # zero statements. `char_ref.absent?` keeps a genuine character
        # reference (`#9829;`) from ever being misread as the start of a
        # comment line here.
        rule(:hash_comment_statement) do
          char_ref.absent? >> hash_char >>
            (line_end.absent? >> any).repeat >> line_end
        end

        # mermaid encodes `/#\w+;/g` globally before its lexer ever runs
        # (see the grammar's design doc for the full citation); this is
        # the regex-equivalent grammar rule, needed wherever a `;`-aware
        # boundary would otherwise split a character reference in half.
        rule(:char_ref) do
          hash_char >> match['a-zA-Z0-9_'].repeat(1) >> semicolon
        end

        # A `;`-aware text capture: a character reference is consumed
        # whole, so its own `;` is never mistaken for a separator. Also
        # stops at a bare `#`, leaving it for `content_boundary`'s
        # trailing-comment consumption — a `#` opens a comment that runs to
        # the physical line end, `;` included.
        #
        # `match['^;\n\r#']` is a bulk fast path: one native scan per run
        # instead of one Parslet alternation per character. It keeps
        # trailing spaces before the boundary inside the run rather than
        # excluding them; every caller either strips via `extract_text` or
        # never reads the label (`alt`/`par`), so that difference is moot.
        rule(:text_run) do
          (char_ref | match['^;\n\r#'].repeat(1)).repeat
        end

        # Runs to the physical line end: testing `line_end` at every
        # character rescans an interior whitespace run each time.
        rule(:rest_of_line) do
          match['^\n'].repeat >> line_end
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
        # `>` joins `<` as never `actor_name` material, matching the same
        # fix applied to `message_actor_char` — it was missing here too.
        # Measured against mermaid 11.16.1 directly: `activate A>B`,
        # `deactivate A>B` and `Note over A>B: n` all raise on mermaid;
        # base created actor `"A>B"` for all three, reading straight past
        # the `>`. Round-2 Codex finding, in scope: same missing exclusion
        # as the message-actor fix, just in the sibling rule that serves
        # activation and note references instead of messages.
        rule(:actor_char) do
          actor_stop.absent? >>
            (match['^+<>-'] |
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
        # `#` is NOT here: mermaid only rejects a LEADING `#`
        # (`declaration_lead`/`declaration_word_lead` below), and lets it
        # through everywhere else in an id — measured against mermaid
        # 11.16.1, `participant A#B` gives id "A#B".
        rule(:declaration_stop) do
          match['<>'] | colon | comma | semicolon | str('%%') |
            str('@') | newline
        end

        rule(:declaration_char) { declaration_stop.absent? >> any }

        # The first character of an id is the only place `#` is ever
        # banned — measured against mermaid 11.16.1: `participant #B`
        # raises, `participant A#B` does not. `char_ref` is tried first so
        # a leading `#9829;` reference is consumed whole rather than
        # rejected by the ban.
        # Shared by `declaration_lead` and `declaration_word_lead` below —
        # both are "char_ref, else a plain character not banned by a
        # leading `#`", differing only in which character rule bounds the
        # plain branch. A private method, not `rule()`: Parslet's `rule()`
        # macro memoizes a fixed zero-argument atom and can't take one.
        def hash_free_lead(char_rule) = char_ref | (hash_char.absent? >> char_rule)
        private :hash_free_lead

        rule(:declaration_lead) { hash_free_lead(declaration_char) }

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

        rule(:declaration_word_lead) { hash_free_lead(declaration_word_char) }

        # Each branch's lead unit bans a leading bare `#`; the repeated
        # tail does not, so a `#` past the first character stays ordinary
        # id material. Both also gain a `char_ref` alternative ahead of
        # their plain character rule, so a `#9829;` run is consumed as one
        # atomic unit. Without it in the alias branch specifically,
        # `#9829;B as Heart` falls through to the fallback branch and
        # swallows the whole thing as an id with no label.
        rule(:declaration_name) do
          (declaration_word_lead >> (char_ref | declaration_word_char).repeat >>
            alias_keyword.present?) |
            (declaration_lead >> (char_ref | declaration_char).repeat)
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
        # `#` is NOT here, matching `declaration_stop`: mermaid only
        # rejects a LEADING `#` on a message endpoint, not one mid-name —
        # measured, `A->>B#C: m` gives recipient "B#C". The leading ban
        # lives in `message_actor_lead_char` below instead, so it applies
        # only to the first character, not to every character that
        # follows this rule via `message_actor_char`.
        rule(:message_actor_stop) do
          arrow_base | colon | comma | semicolon | str('%%') |
            str('@{') | lparen | rparen | newline
        end

        # FOUR rounds of patching this rule each found a new gap, and the
        # fourth (a differential fuzz against mermaid, 10,568 generated
        # inputs, all 1,939 sirena-accepted ones cross-checked in Chrome
        # — this grammar's own hand-written approximations had exhausted
        # every gate we already had) found two more, both the SAME shape
        # as the first three: a HAND-DERIVED stand-in for a piece of
        # mermaid's real regex, each stand-in accurate on the cases it
        # was checked against and wrong on one it wasn't. The fix each
        # time was to stop deriving and start copying:
        #
        # - The regex has TWO SEPARATE things where this rule had
        #   conflated them into one per-character check: an ENTRY
        #   lookahead, evaluated ONCE at the position of the triggering
        #   dash, and a TAIL character class, evaluated per character
        #   while consuming the run that follows. Round 3's version
        #   re-ran a stop-check (including `arrow_base` and sirena's own
        #   `%%`/`@{` extensions) at EVERY tail character, which is not
        #   what the real regex does — its tail class
        #   (`[^\+<\->\->:\n,;]`) is a flat set with no arrow-awareness
        #   at all. Measured: `B->>A-(%%C: m` — mermaid consumes the
        #   embedded `%%` as ordinary tail material and sends message
        #   "m"; the per-character recheck stopped there instead,
        #   producing recipient "A-(" and an EMPTY message. Same root
        #   cause exposed `A-(//-B: m`: mermaid reads the whole
        #   "A-(//-B" as one actor and rejects the missing arrow; the
        #   recheck matched `arrow_base`'s reversed-arrow spelling
        #   mid-tail and stopped there instead, letting `->>` parse as a
        #   real arrow it should never have reached.
        #   `message_actor_continuation_tail_char` below is now the
        #   regex's OWN flat class, ported directly rather than built
        #   from sirena's existing rule references.
        # - The entry lookahead itself was still incomplete: `arrow_base`
        #   (independently verified, unchanged across all four rounds)
        #   covers every COMPLETE arrow spelling, but mermaid's lookahead
        #   ALSO independently bans a bare `-/` and a bare `-\` even when
        #   nothing arrow-shaped ever follows — measured directly against
        #   the compiled lookahead: `"A-/ZZZ"` and `"A-\ZZZ"` both stop
        #   at `"A"`, same as `"A--ZZZ"`, while `"A-fooZZZ"`,
        #   `"A-(ZZZ"` and `"A-%ZZZ"` all continue past it. No
        #   `arrow_base` alternative is exactly "-/" or "-\" — every
        #   slash/backslash spelling in `reversed_arrow` needs a THIRD
        #   character sirena already covers, or a fourth like `-//`
        #   which `solid_arrow` already has. `-/` and `-\` alone were
        #   simply missing, so `B->>A-/(): m` and `B->>A-\(): m` fused
        #   the guard character into the identity instead of refusing.
        #   `message_actor_continuation_entry_stop` below adds exactly
        #   those two, verified empirically against every candidate
        #   prefix the compiled lookahead actually protects, not
        #   re-derived from the regex source text a second time (that is
        #   how `-/` was missed the first time — hand-reading nested
        #   backslash escapes in a 200-character alternation).
        rule(:message_actor_continuation_entry_stop) do
          arrow_base | str('--') | str('-/') | str('-\\')
        end

        # The regex's own tail class, `[^\+<\->\->:\n,;]`, transliterated
        # directly: excludes only `+ < - > : \n , ;`. No arrow-awareness,
        # no `%%`/`@{` — those are sirena's OWN extensions for comments
        # and shape metadata, real everywhere ELSE in this grammar, but
        # never part of mermaid's ACTOR token and specifically NOT part
        # of an already-open fusion tail (finding 1's `%%` case above).
        # `\r` sits alongside `\n` because sirena's own `newline` rule
        # (used elsewhere) accepts CRLF; excluding both characters
        # individually gives the same boundary a rule-based check would,
        # without needing a rule reference inside a character class.
        rule(:message_actor_continuation_tail_char) do
          match["^+<>:\n\r,;-"]
        end

        rule(:message_actor_continuation) do
          message_actor_continuation_entry_stop.absent? >> str('-') >>
            message_actor_continuation_tail_char.repeat(1)
        end

        # CORRECTED (round 5): the EOF case this comment used to justify
        # keeping this branch no longer reaches a successful parse at all —
        # `A->>B-` at true end of file now raises (spec: "rejects a
        # trailing dash recipient at true end of file"), because THIS diff
        # makes `message_text` mandatory. `message_actor_stop` never
        # matches at true EOF, so the branch still consumes the trailing
        # dash, but nothing is left to satisfy the now-required `: text`.
        # Whether that makes the branch fully unreachable was not
        # re-derived here — removing it is a separate, unverified change
        # from the four rules this diff scopes; left in place rather than
        # deleted on an unverified claim.
        # A dash followed by `/` or `\` ends the name, as it does for a
        # continuation: `A->>B-/C: m` and `A->>B-\C: m` are rejected.
        rule(:message_actor_char) do
          message_actor_stop.absent? >>
            (match['^+<>()-'] |
              (str('-') >>
                (str('-') | str('/') | str('\\') | message_actor_stop).absent?))
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
        #
        # `|` does NOT join this set: no arrow spelling starts with a bare
        # `|` (the pipe-bearing spellings — `-|/`, `-|\`, `--|/`, `--|\` —
        # all need a leading dash first, which `message_actor_lead` already
        # never consumes). Measured against mermaid 11.16.1: `A-->|: m` and
        # `A-x|: m` both give recipient `"|"` verbatim; a leading pipe is
        # ordinary actor-name material, not a collision to protect against.
        #
        # The LEAD-only character rule for point 1 above: the plain
        # character class only, deliberately WITHOUT `message_actor_char`'s
        # dash branch, so a message actor name can never open with `-` —
        # neither `-foo`, `-B`, `-()`, nor `- ()`. `hash_char.absent?` bans
        # a LEADING bare `#` only — `message_actor_stop` no longer does,
        # so a `#` past the first character stays ordinary name material
        # (measured, `A->>B#C: m` gives recipient "B#C").
        rule(:message_actor_lead_char) do
          message_actor_stop.absent? >> hash_char.absent? >> match['^+<>()-']
        end

        # `char_ref` is tried first so a name can OPEN with a character
        # reference (`links #9829;B: {}`) — the reference is consumed
        # whole, before `message_actor_lead_char`'s `#` ban would otherwise
        # stop the plain branch at its very first character.
        rule(:message_actor_lead) do
          char_ref |
            (match[')>/\\\\'].absent? >> mermaid_token_opener.absent? >>
              message_actor_lead_char)
        end

        # Where mermaid's lexer starts a token, two of its rules run before
        # its actor rule and take the text instead, so a message endpoint
        # can never start with either:
        #
        # - `%` not opening `%{`: the rest of the line is a comment.
        #   `A->>%B: m` is rejected; `A->>%{x: m` is not.
        # - a number followed by a space or newline: it is read as a
        #   number, not a name. `A->>8 : m` and `1 ->> 2: m` are rejected;
        #   `A->>8: m` and `A->>1.555 : m` (three decimals) are not.
        #
        # A `%%` right after an endpoint's first character needs no rule
        # here: `%%` already ends the name, and the comment it opens leaves
        # the message without its required `: text`.
        rule(:mermaid_token_opener) do
          (str('%') >> str('{').absent?) |
            (lexed_number >> match[" \n"])
        end

        rule(:lexed_number) do
          (match['0-9'].repeat(1) >>
            (str('.') >> match['0-9'].repeat(1, 2)).maybe) |
            (str('.') >> match['0-9'].repeat(1, 2))
        end

        # `message_actor_continuation` is tried only in the repeat below —
        # never as part of `message_actor_lead` above — which combined
        # with the lead using `message_actor_lead_char` (not
        # `message_actor_char`) is what makes an empty prefix before a
        # dash-fusion unreachable from either direction. Tried before the
        # plain `message_actor_char` branch since it is the more specific
        # case and Parslet alternation is first-match.
        rule(:message_actor_name) do
          message_actor_lead >>
            (char_ref | message_actor_continuation | message_actor_char).repeat
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

        # Participant declarations. `keyword` and `id`/`label` are shared
        # by the plain declarations below and by `create_statement`, so
        # `create participant Carl` inherits `declaration_name`'s char-ref
        # fix for free the same way a bare `participant Carl` does — a
        # private method, not `rule()`, since only the TERMINATOR differs
        # between the two callers (see `create_statement`'s comment).
        def declaration_body(keyword)
          str(keyword) >> space.repeat(1) >>
            declaration_name.as(:id) >> shape_metadata.maybe >> space? >>
            (str('as') >> space.repeat(1) >> label.as(:label)).maybe
        end
        private :declaration_body

        # Ends at `content_boundary`, not `line_end` — a declaration can be
        # followed by another statement on the same line after a `;`, and
        # `line_end` only accepts one right before a newline. Measured
        # against mermaid 11.16.1: `participant A;participant B;A->>B: m`
        # gives 2 participants, 1 message; `line_end` alone rejected it
        # outright, since it has nowhere to put the text still left after
        # its own leading `;`.
        rule(:participant_declaration) do
          declaration_body('participant') >> content_boundary.as(:participant)
        end

        rule(:actor_declaration) do
          declaration_body('actor') >> content_boundary.as(:actor)
        end

        # `.as(:create)` is required: the builder's lifecycle check (see
        # `Builders::Sequence`) branches on this key to register the
        # pending create; without it a `create` is silently unchecked.
        # Same `content_boundary` terminator as the two plain declarations
        # above, for the same inline-`;` reason. Measured against mermaid
        # 11.16.1: `create participant B;A->>B: m` gives 2 participants,
        # 1 message.
        rule(:create_statement) do
          str('create').as(:create) >> space.repeat(1) >>
            ((declaration_body('participant') >> content_boundary.as(:participant)) |
              (declaration_body('actor') >> content_boundary.as(:actor)))
        end

        # Draws no destroy marker (sirena's existing "not modeled" stance
        # on decorative constructs) — `.as(:destroy)` still captures the
        # target id because the lifecycle check needs it to register the
        # pending destroy against the very next message.
        #
        # Ends at `content_boundary` for the same inline-`;` reason as
        # `create_statement` above: `destroy B;A->>B: m` gives 2
        # participants, 1 message on mermaid 11.16.1; `line_end` alone
        # rejected it.
        rule(:destroy_statement) do
          str('destroy') >> space.repeat(1) >>
            declaration_name.as(:destroy) >> content_boundary
        end

        # Target uses `message_actor_name`, not `declaration_name` like
        # `participant`/`actor`/`destroy` — don't "fix" that; its bans on
        # `()`/`#`/leading dash come from `message_actor_stop`/
        # `message_actor_lead_char`. `.as(:links)` looks unread but isn't:
        # the builder uses it to call `ensure_participant`. Payload is
        # unvalidated JSON, like `shape_metadata`, and stops at
        # `content_boundary` (not `rest_of_line`) so an inline `;` always
        # yields the following message instead of swallowing it.
        rule(:links_statement) do
          str('links') >> space.repeat(1) >>
            message_actor_name.as(:links) >> colon >> text_run >> content_boundary
        end

        # Messages with arrows (order matters: longest patterns first)
        rule(:message) do
          message_actor_name.as(:from) >> space? >>
            message_signal.as(:arrow) >> space? >>
            message_actor_name.as(:to) >> space? >>
            message_text.as(:text) >>
            content_boundary
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
            text_run.as(:message_text)
        end

        # Notes
        rule(:note_statement) do
          (str('note') | str('Note')) >> space.repeat(1) >>
            note_position.as(:position) >> space.repeat(1) >>
            note_participants.as(:participants) >> space? >>
            colon >> space? >>
            text_run.as(:note_text) >>
            content_boundary
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
            text_run.as(:box_label) >> content_boundary >>
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
            text_run.as(:loop_label) >> content_boundary >>
            ws? >>
            statements.as(:loop_statements) >>
            ws? >>
            str('end') >> line_end
        end

        # Every block-opening/continuation label (this one through
        # `break_label`) must use `text_run`, never its own end-of-line
        # scan: mermaid's real lexer tokenizes all of them — `loop`, `alt`,
        # `else`, `opt`, `par`, `and`, `critical`, `option`, `break`, `box`
        # — through one shared state whose label rule stops at `;`. `rect`
        # has no rule in this grammar at all.
        rule(:alt_structure) do
          str('alt') >> space? >>
            text_run.as(:alt_label) >> content_boundary >>
            ws? >>
            statements.as(:alt_statements) >>
            ws? >>
            (
              str('else') >> space? >>
              text_run.as(:else_label) >> content_boundary >>
              ws? >>
              statements.as(:else_statements) >>
              ws?
            ).repeat.as(:else_blocks) >>
            str('end') >> line_end
        end

        # `match['a-zA-Z0-9_'].absent?` after the literal `opt` is a real
        # word-boundary guard, not just a bare literal: without it, this
        # rule matches `opt` as a PREFIX of `option` (case 041's
        # `option Network timeout` line inside a `critical` block was
        # misread as a nested `opt` with label `"ion Network timeout"`,
        # consuming the real closing `end` and breaking the whole parse).
        # Verified mermaid also rejects a glued `optFoo`.
        rule(:opt_structure) do
          str('opt') >> match['a-zA-Z0-9_'].absent? >> space? >>
            text_run.as(:opt_label) >> content_boundary >>
            ws? >>
            statements.as(:opt_statements) >>
            ws? >>
            str('end') >> line_end
        end

        rule(:par_structure) do
          str('par') >> space? >>
            text_run.as(:par_label) >> content_boundary >>
            ws? >>
            statements.as(:par_statements) >>
            ws? >>
            (
              str('and') >> space? >>
              text_run.as(:and_label) >> content_boundary >>
              ws? >>
              statements.as(:and_statements) >>
              ws?
            ).repeat.as(:and_blocks) >>
            str('end') >> line_end
        end

        rule(:critical_structure) do
          str('critical') >> space? >>
            text_run.as(:critical_label) >> content_boundary >>
            ws? >>
            statements.as(:critical_statements) >>
            ws? >>
            (
              str('option') >> space? >>
              text_run.as(:option_label) >> content_boundary >>
              ws? >>
              statements.as(:option_statements) >>
              ws?
            ).repeat.as(:option_blocks) >>
            str('end') >> line_end
        end

        rule(:break_structure) do
          str('break') >> space? >>
            text_run.as(:break_label) >> content_boundary >>
            ws? >>
            statements.as(:break_statements) >>
            ws? >>
            str('end') >> line_end
        end

        # Label can be quoted or unquoted text
        rule(:label) do
          string | unquoted_label
        end

        # Only caller is `declaration_body`'s alias branch, shared by
        # `participant`/`actor`/`create`. Stops at an inline `;` for the
        # same reason `declaration_body`'s own terminator does below —
        # without it, `participant B as Bee;A->>B: m` reads the whole
        # `;A->>B: m` into the label instead of leaving it for the next
        # statement. Measured against mermaid 11.16.1: `B` gets label
        # "Bee", and `A->>B: m` parses as a separate message.
        rule(:unquoted_label) do
          (line_end.absent? >> semicolon.absent? >> any).repeat(1)
        end
      end
    end
  end
end
