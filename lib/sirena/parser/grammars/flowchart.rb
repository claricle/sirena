# frozen_string_literal: true

require_relative 'common'
require_relative 'mermaid_unicode_text'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Flowchart diagrams.
      #
      # Handles flowchart syntax including nodes with various shapes,
      # edges with labels, edge chaining, subgraphs, and styling directives.
      class Flowchart < Common
        # Mermaid lexes these as keywords, so `end.` and `1end` are not
        # node ids even though the characters are legal.
        #
        # `direction`, `accTitle`, `accDescr`, `default` and `callback` are
        # NOT among them — mmdc draws `default-->Z`. `href`, `call` and
        # `click` are keywords too but end a word differently, so they live
        # in `spaced_keyword` instead. `direction TB` on its own line is
        # still not parsed here, though mmdc draws it.
        #
        # Longest first, because Parslet does not backtrack into an
        # alternative that already matched: `class` ahead of `classDef`
        # would take the first five characters and then fail the boundary.
        RESERVED_WORDS = %w[
          swimlane-beta interpolate flowchart linkStyle subgraph classDef
          _parent _blank _self graph style class _top end
        ].freeze

        # The words reserved in a subgraph id, which is NOT the node list.
        # A statement keyword is plain text here (`subgraph graph [T]`
        # renders), so those drop out. `default` is reserved here and
        # nowhere else: `subgraph default [T]` does not render while
        # `default-->Z` does.
        SUBGRAPH_RESERVED = %w[
          interpolate _parent default _blank _self _top
        ].freeze
        private_constant :RESERVED_WORDS, :SUBGRAPH_RESERVED

        # Mermaid restarts its lexer at certain characters and looks for
        # the target again behind each restart. Several rules walk that
        # path, so they share it here.
        #
        # A `repeat` rather than a recursive rule: a recursive one blew the
        # Ruby stack on a 2000-character id that mmdc draws.
        def token_at_lexer_restart(target)
          (target.absent? >> restart_step).repeat >> target
        end
        private :token_at_lexer_restart

        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # The direction shares the keyword's line, so `graph` newline `TD`
        # is a diagram with a node called TD. Nothing else may follow the
        # keyword: mmdc refuses `graph X;A`, `graph ;A` and `graph TDx`.
        # A word direction needs a gap; a glyph one does not. mmdc renders
        # `graph<` and `graph >` alike, and refuses `graphTD`.
        #
        # The two branches exist because a separator only closes the header
        # when a direction came first — `graph TD;A` renders and `graph;A`
        # does not. A lookahead cannot tell them apart: by the time the
        # header ends, the direction has already been consumed.
        rule(:header) do
          (str('flowchart') | str('graph')).as(:header) >>
            (directed_header | undirected_header)
        end

        rule(:directed_header) do
          header_direction.as(:direction) >>
            (separator | space? >> (newline | eof))
        end

        rule(:undirected_header) do
          direction.absent?.as(:direction) >> space? >> (newline | eof)
        end

        rule(:header_direction) do
          space.repeat(1) >> direction |
            glyph_direction.as(:dir_value)
        end

        # A `;` between statements on one line. `line_end` is deliberately
        # left alone: `style_property` and `click_action` scan a value up to
        # the physical end of the line via `line_end.absent?`, so widening it
        # would truncate `style A fill:#f9f;stroke:#333` at the semicolon.
        #
        # Repeat only this rule, never `statement_end` — the `line_end` arm
        # succeeds zero-width at EOF, so repeating that would not terminate.
        # A comment cannot open on the same line as the separator: mmdc
        # rejects `graph TD;%% c`, while `;` then a newline then `%% c` is
        # ordinary.
        rule(:separator) do
          (semicolon >> space?).repeat(1) >> str('%%').absent?
        end

        # Node statements tolerate a space before the separator
        # (`graph TD;A ;`). The header and a class assignment do not: mmdc
        # rejects `graph TD ;A` and `class A foo ;B`.
        rule(:loose_separator) { space? >> separator }

        rule(:statement_end) { separator | line_end }
        rule(:loose_statement_end) { loose_separator | line_end }

        # mermaid's full set, aliases included: `BR` and `v` are another
        # down, and three arrow glyphs stand in for the words. `v` is a
        # word here, not a glyph — it needs the same gap `TD` does, while
        # `<`, `>` and `^` do not.
        rule(:direction) { (word_direction | glyph_direction).as(:dir_value) }

        rule(:word_direction) do
          str('TD') | str('TB') | str('BT') | str('BR') | str('LR') |
            str('RL') | str('v')
        end

        # These three need no gap after the keyword — mmdc draws `graph<`.
        rule(:glyph_direction) { match['<>^'] }

        # `direction LR` inside a subgraph turns that box's contents.
        # mmdc 11.12.0 accepts a top-level one too but does not honour it,
        # so it is a statement anywhere and the transform decides whether
        # anything encloses it.
        # `statement_end`, not `line_end`: a semicolon separates this from
        # the next statement the way it separates every other one. mmdc
        # 11.12.0 renders `direction LR;A`, and `line_end` takes the
        # semicolon only when a newline follows it.
        rule(:direction_statement) do
          str('direction').as(:direction_keyword) >> space >>
            statement_direction >> statement_end
        end

        # The five plain words only, NOT the header's set. mmdc takes
        # `graph <`, `graph v` and `graph BR`, and refuses every one of
        # them after `direction` — measured on 11.12.0. Reusing the
        # header rule here accepted three sources mermaid will not draw.
        rule(:statement_direction) do
          (str('TD') | str('TB') | str('BT') | str('LR') |
            str('RL')).as(:dir_value)
        end

        rule(:statements) do
          ((separator | statement) >> ws?).repeat(1)
        end

        rule(:statement) do
          accessibility_statement |
            direction_statement |
            subgraph_statement |
            style_statement |
            class_def_statement |
            class_assignment_statement |
            click_statement |
            node_edge_statement |
            standalone_node
        end

        # `accTitle:` and `accDescr:` carry the text mermaid puts in the
        # SVG's aria attributes.
        rule(:accessibility_statement) do
          acc_descr_block | acc_line
        end

        # Mermaid separates the keyword from its delimiter with \s*, which
        # crosses newlines, so the gap here is `acc_gap` and not `space?`.
        # It is whitespace only, never a comment: mmdc keeps `%% comment`
        # in `accTitle: %% comment` as the title text.
        #
        # The text runs to the PHYSICAL end of the line, not to `line_end`,
        # for the same reason: a `%%` inside a title is ordinary text.
        # The text may be empty — mmdc renders `accTitle:` with nothing
        # after it.
        rule(:acc_line) do
          (str('accTitle') | str('accDescr')).as(:acc_keyword) >>
            acc_gap >> str(':') >> acc_gap >>
            (newline.absent? >> any).repeat.as(:acc_text) >> (newline | eof)
        end

        # Whitespace crosses newlines, and once a newline is crossed a
        # STANDALONE comment line is skipped whole: mmdc reads
        # `accTitle:` newline `%% c` newline `Real` as the title `Real`.
        # A comment on the delimiter's OWN line stays text, which is why
        # the skipping only starts after the first newline.
        rule(:acc_gap) do
          line_space.repeat >>
            (newline >> (line_space | newline | comment).repeat).repeat
        end

        # Whitespace that stays on the line: mermaid's `\s` without the
        # newline. It is wider than a space and a tab — mmdc reads
        # `accTitle` no-break-space `:` as a title.
        #
        # No carriage return: the parser folds every one into a newline
        # before the grammar sees it, the way mermaid does.
        #
        # Ruby's `[[:space:]]` is not the same set in either direction. It
        # misses U+FEFF, which mmdc treats as a space, and it adds U+0085,
        # which mmdc does not. So the set is spelled out here.
        rule(:line_space) do
          match['\t\v\f \u00A0\u1680' \
            '\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF']
        end

        # Mermaid deletes whole comment LINES before it parses anything,
        # so a `}` inside one does not close a block: `accDescr {` /
        # `text` / `%% }` swallows every line after it.
        #
        # A comment starts at a newline and stops at its own line end,
        # leaving that newline behind. The next line claims it, which is
        # how two comment lines in a row both match, and running out of
        # source just ends the repeat. The strip is anchored to the line
        # start, so mmdc closes the block in `accDescr {text %% }`.
        rule(:comment_line) do
          newline >> line_space.repeat >> str('%%') >>
            (newline.absent? >> any).repeat
        end

        rule(:acc_block_body) do
          (comment_line | (str('}').absent? >> any)).repeat
        end

        # The block form ends at its closing brace, with no line end
        # required after it: mermaid renders `accDescr {Desc}A-->B`.
        #
        # An unterminated block runs to the end of the source rather than
        # failing, because mmdc draws `accDescr {Unterminated` and
        # swallows every line after it.
        rule(:acc_descr_block) do
          str('accDescr').as(:acc_keyword) >> acc_gap >> str('{') >>
            acc_block_body.as(:acc_text) >>
            (str('}') >> line_space.repeat >> semicolon.maybe).maybe
        end

        # Subgraph: subgraph id [title] ... end, or `subgraph id title`
        # with the rest of the line as the title.
        rule(:subgraph_statement) do
          str('subgraph').as(:subgraph_keyword) >> space >>
            subgraph_id.as(:subgraph_id) >>
            subgraph_name_and_title >>
            declaration_end >>
            ws? >>
            statements.maybe.as(:subgraph_statements) >>
            ws? >>
            str('end').as(:subgraph_end) >>
            subgraph_close
        end

        # What sits between the subgraph id and the end of its line.
        #
        # Two readings met here. This branch reads the rest of the line as
        # the box TITLE, because the cluster renderer needs that text. The
        # `end`-word walk on main reads extra WORDS in front of an optional
        # bracketed title and throws the words away. Both are kept: the
        # title is tried first, and it only wins when it reaches the end of
        # the declaration, so `subgraph A Title` is titled `A Title` while
        # `subgraph A B [T]` still falls through to the word walk and is
        # titled `T`.
        rule(:subgraph_name_and_title) do
          (subgraph_title >> declaration_end.present?) |
            subgraph_trailing_name
        end

        # The declaration owns the rest of its line. A bracketed title has
        # to be the last thing on it — mmdc refuses `subgraph s [T] A` and
        # `subgraph s [T] %% note`, while `subgraph s %% note` is fine
        # because the comment simply becomes the title text.
        # All the whitespace, not just the first space: consuming one let
        # `subgraph s  [Title] A` slip past the bracket guard below and be
        # read as free text, which mmdc refuses.
        # A bracketed title may sit straight against the id — mmdc renders
        # `subgraph s[Title]` — while a free one needs a gap to start.
        # The gap is captured, not just skipped. A free title's label is
        # the source from the id onwards, so `subgraph s  Title` is
        # labelled `s  Title` and collapsing the run would misquote it.
        rule(:subgraph_title) do
          space.repeat >> bracketed_title |
            space.repeat(1).as(:subgraph_free_gap) >> free_title
        end

        rule(:bracketed_title) { bracket_title >> bracket_title_end }

        rule(:bracket_title) do
          lbracket >> (rbracket.absent? >> any).repeat(1).as(:subgraph_title) >>
            rbracket
        end

        # Nothing at all may follow a bracketed title, not even a space:
        # mmdc refuses `subgraph s [Title] ` before the newline.
        rule(:bracket_title_end) do
          (semicolon_run >> no_comment | newline | eof).present?
        end

        # A flat character class, NOT `declaration_end.absent? >> any`.
        # That re-ran `space?` at every byte, so a title carrying a run of
        # spaces parsed in quadratic time — 4k spaces took 3.7 seconds and
        # 16k took over a minute, on a source mmdc renders.
        #
        # The structural characters are excluded because mermaid refuses
        # them here: `subgraph s Title (More)`, `<More>` and `{More}` are
        # all rejected.
        rule(:free_title) do
          lbracket.absent? >>
            (title_run >> (space.repeat(1) >> title_run).repeat)
              .as(:subgraph_free_title)
        end

        rule(:title_run) { comment_word | title_word }

        # Mermaid only strips a comment at the start of a line, so behind
        # the id it stays text and owns the rest of the line.
        rule(:comment_word) do
          str('%%') >> (newline.absent? >> any).repeat
        end

        # Main's guarded name word, not a loose character run. A free
        # title's words are the same words a trailing name may hold, so
        # `subgraph A end` and `subgraph A interpolate` stay refused while
        # the text still becomes the box title.
        rule(:title_word) { subgraph_name_word }

        # A semicolon run separates statements here as it does after `end`,
        # and a comment is not a statement: mmdc renders `subgraph s;;A`
        # and refuses `subgraph s; %% note`.
        rule(:declaration_end) do
          line_space.repeat >> (semicolon_run >> no_comment | newline | eof)
        end

        rule(:subgraph_close) do
          space.repeat(1) >> close_at_space |
            space? >> (close_at_line_end | close_at_semicolon)
        end

        # Whitespace alone separates `end` from what follows: mmdc renders
        # `end B-->C`. Referencing `statement` here would be recursive, so
        # the guard is what a statement cannot start with — a comment, a
        # separator, or the end of the line.
        rule(:close_at_space) do
          (str('%%') | semicolon | newline | eof).absent?
        end

        # `end` finishes its line, with any number of trailing semicolons.
        # Nothing else may follow, so `end %% note` is refused here — mmdc
        # takes `end` and then a comment on its own line.
        rule(:close_at_line_end) do
          semicolon_run.maybe >> space? >> (newline | eof)
        end

        # A semicolon separates statements, so the next one may sit on the
        # same line: mmdc renders `end; B-->C` and `end;end`. A comment is
        # still not a statement, and `end; %% note` is refused.
        rule(:close_at_semicolon) do
          semicolon_run >> str('%%').absent?
        end

        rule(:semicolon_run) { (semicolon >> space?).repeat(1) }

        # A comment is not a statement, so it cannot follow a separator on
        # the same line: mmdc refuses `end; %% note` and
        # `subgraph s; %% note`.
        rule(:no_comment) { str('%%').absent? }

        # An unbracketed name runs on past the first space: mermaid titles
        # `subgraph 1 abc` "1 abc". Every trailing word carries the same
        # guards as the first one, `end` included, because they all go
        # through `subgraph_name_word`. So mmdc's refusals
        # (`subgraph A interpolate`, `subgraph A 1default`,
        # `subgraph A .-`) are refused here too, while `subgraph A end [T]`
        # and `subgraph A end B` draw: what ends a subgraph is `end` with
        # the LINE behind it, the position and not the word.
        #
        # The charset is narrower than mermaid's title text, so only id
        # words are consumed. mmdc titles `subgraph A B:C` "A B:C" and this
        # refuses it — left for a change that models mermaid's own
        # `textNoTags` production. Nothing reads the name yet, so the extra
        # words are consumed, not kept.
        #
        # The bracketed title comes AFTER those words and this is the only
        # rule that reads it, so `subgraph A B [T]` and `subgraph A B C [T]`
        # draw. `subgraph A [T] X` stays refused, as mmdc refuses it:
        # nothing may follow the title on the line.
        rule(:subgraph_trailing_name) do
          (space.repeat(1) >> subgraph_name_word).repeat >>
            subgraph_title.maybe
        end

        rule(:subgraph_end_word) { str('end') >> word_boundary }

        # Style: style nodeId fill:#f9f
        rule(:style_statement) do
          str('style').as(:style_keyword) >> space >>
            reserved_keyword.absent? >> node_id.as(:style_target) >>
            (space >> style_property_list).as(:style_props) >>
            statement_end
        end

        # What a `;` does inside a declaration turns on the value, not on
        # the text after it:
        #
        #   style A fill:red;B    -> nodes A and B  (the `;` ends the style)
        #   style A fill:#f9f;B   -> node A only    (the `;` is value text)
        #
        # The plain branch is guarded rather than merely second, so a bad
        # hashed tail fails the statement instead of falling through and
        # drawing a node mermaid refuses.
        rule(:style_property_list) do
          hashed_property_list | hashed_head.absent? >> style_property
        end

        # After a `#` the declaration carries at most one `;`. mmdc
        # takes `fill:#f9f;stroke:#333` and `fill:#f9f;B`, and refuses
        # `fill:#f9f;B;C` and `fill:#f9f;;B`, so the tail has to end at the
        # line rather than hand a second `;` back as a separator.
        rule(:hashed_property_list) do
          hashed_head >> declaration_char.repeat >>
            (semicolon >> space? >> hashed_tail | semicolon.absent?)
        end

        # The `#` has to arrive before the first `;` for the swallow to
        # start: mmdc reads `style A fill:red;stroke:#333` as a style plus a
        # node, because the `;` comes first.
        rule(:hashed_head) do
          (hash.absent? >> declaration_char).repeat >> hash
        end

        # What may follow that one `;` is a style component, not a node and
        # not an edge, so it stops at anything structural. It ends where
        # `line_end` ends and nowhere else: a `%%` here is ordinary
        # declaration text.
        rule(:hashed_tail) do
          (structural_token.absent? >> declaration_char).repeat >>
            space? >> (newline | eof).present?
        end

        # What mermaid keeps for shapes and edges. It is refused wherever
        # mermaid expects a bare word — in a style declaration after a `#`
        # and in a callback name alike.
        rule(:structural_token) { compound_token | structural_char }

        # Some of what mermaid reserves is longer than one character, and
        # every character in it is legal on its own. In a style tail and in
        # a callback name alike, `B-C`, `B.C` and `B::C` are ordinary text
        # while `B--C`, `B-.C` and `B:::C` are errors.
        rule(:compound_token) { str(':::') | str('--') | str('-.') }

        # The single-character half of the set. Every other printable ASCII
        # character is fine in both places.
        rule(:structural_char) { match['\\[\\]{}()<>|~@=^'] }

        rule(:declaration_char) do
          line_end.absent? >> semicolon.absent? >> comma.absent? >> any
        end

        # Permissive: mermaid takes `style A red`, `style A fill:` and
        # `style A fill :red`, so `name:value` is not required. One
        # character minimum though — mmdc refuses a bare `style A`.
        #
        # Without a hash the `;` always ends the statement, so a second
        # declaration is left to be parsed as one. mermaid draws
        # `style A fill:red;stroke:blue` as a style plus a node called
        # `stroke:blue`; a node id here takes no colon, so we refuse the
        # line rather than draw a diagram one node short.
        rule(:style_property) { declaration_char.repeat(1) }

        # ClassDef: classDef className fill:#f9f
        rule(:class_def_statement) do
          str('classDef').as(:classdef_keyword) >> space >>
            identifier.as(:class_name) >>
            (space >> style_property_list).as(:class_props) >>
            statement_end
        end

        # Class assignment: class nodeId className
        rule(:class_assignment_statement) do
          str('class').as(:class_keyword) >> space >>
            reserved_keyword.absent? >> node_id.as(:class_target) >> space >>
            identifier.as(:class_name) >>
            statement_end
        end

        # Click: click nodeId href (may not fully implement, just parse)
        #
        # The gap after the keyword is a RUN of whitespace, unlike the one
        # before the action. mermaid opens its click state on `"click"\s+`,
        # so mmdc draws `click  A "url"` where a single space refused it.
        rule(:click_statement) do
          str('click').as(:click_keyword) >> space.repeat(1) >>
            click_target.as(:click_target) >>
            (space >> click_action.as(:click_action)) >>
            statement_end
        end

        # An action is required — mmdc rejects a bare `click A`. mermaid
        # takes exactly four shapes here and anything else is an error, so
        # the action is spelled out rather than scanned to the end of the
        # line.
        #
        # Every gap between these tokens is ONE space or ONE tab. mermaid
        # counts the characters: `click A href  "u"`, `"u"  "tip"` and
        # `"u"  _blank` are all errors. Only inside a `call` is whitespace
        # free-form.
        rule(:click_action) do
          callback_action | href_action | link_action | callback_name_action
        end

        # `click A call cb(foo;bar)` — the semicolon belongs to the callback
        # argument list, so the parens are only special after `call`.
        #
        # The name runs to the opening paren, dots and semicolons included:
        # mmdc reads `call cb;B()` as one callback named `cb;B`, and takes
        # `call ns.cb()` and any run of spaces after `call`.
        #
        # Only a quoted tooltip may trail the parens. mmdc refuses
        # `call cb() _blank` and `call cb() nope`, which the old open-ended
        # tail accepted.
        rule(:callback_action) do
          call_opener >> callback_name >>
            callback_gap? >> lparen >>
            (rparen.absent? >> any).repeat >> rparen >>
            (space >> quoted_run).maybe
        end

        # Once `call` has opened a callback the parens are compulsory: mmdc
        # exits 1 on `click A call cb`.
        rule(:call_opener) { str('call') >> callback_gap }

        # mermaid stops caring about line structure inside a callback, so
        # whitespace and comments are ignorable after `call` and again
        # before the `(`. mmdc renders all four of `call cb()`,
        # `call` nl `cb()`, `call cb` nl `()` and `call cb` nl `%% c` nl
        # `()`.
        rule(:callback_gap) { (space | newline | comment).repeat(1) }
        rule(:callback_gap?) { callback_gap.maybe }

        # The name still stops at the end of its line. mermaid keeps reading
        # past it — `call cb` nl `B --> C` nl `D()` swallows the whole edge
        # and draws neither B nor C — and following it there would let a
        # callback eat statements we can still draw.
        rule(:callback_name) do
          (lparen.absent? >> line_end.absent? >> any).repeat(1)
        end

        # `href` takes a quoted url, then at most a quoted tooltip and a
        # link target, in that order. mmdc refuses `href` on its own,
        # `href cb`, `href "u" nope` and a third quoted run.
        rule(:href_action) { str('href') >> space >> quoted_run >> link_tail }

        # The same shape without the keyword: `click A "u" "tip" _blank`.
        rule(:link_action) { quoted_run >> link_tail }

        # A quoted tooltip then a link target, both optional and in that
        # order. mmdc refuses `"u" _blank "tip"` and a third quoted run.
        rule(:link_tail) do
          (space >> quoted_run).maybe >> (space >> link_target).maybe
        end

        # A bare token is a callback name, and only a quoted tooltip may
        # follow it. mmdc draws `click A clickByFlow "Add a div"` and
        # `click A http://x`, and refuses `click A cb _blank` and
        # `click A my callback`.
        rule(:callback_name_action) do
          bare_token >> (space >> quoted_run).maybe
        end

        # A bare token runs to the first space, `;` or structural token,
        # so `click A cb()` and `click A cb--x` are errors and
        # `click A http://x;B` draws both nodes. A quote only opens a url
        # when it comes first — mmdc draws `click A cb"x`. A keyword is
        # not a callback name either: mmdc refuses `click A href`,
        # `click A end` and `click A _blank`, and takes `click A callback`
        # and `click A clickByFlow`.
        rule(:bare_token) do
          reserved_keyword.absent? >> str('"').absent? >>
            token_char >> token_char.repeat
        end

        rule(:token_char) do
          space.absent? >> line_end.absent? >> semicolon.absent? >>
            structural_token.absent? >> any
        end

        # Never empty. mmdc refuses `click A ""` and every empty tooltip,
        # and takes `click A " "`.
        rule(:quoted_run) do
          str('"') >> (str('"').absent? >> any).repeat(1) >> str('"')
        end

        # A statement keyword is not a node id. Without this a malformed
        # directive falls through to the node rules: `click ;B` would
        # produce nodes `click` and `B`, and mmdc rejects the whole source.
        #
        # The same words that end an id end a statement, so this asks
        # `node_keyword` rather than keeping a second list to drift out of
        # step. Every call site spells `reserved_keyword.absent? >> node_id`.
        rule(:reserved_keyword) { node_keyword }

        # `click`, `href` and `call` are directive words wherever a space,
        # a newline or the end of input follows, and ordinary node ids
        # before a `;` or a shape. mmdc refuses `href --- B`, `call --- B`
        # and a bare `href`, and draws `href;B` and `href[x]` as nodes — so
        # the reservation hangs off the boundary, not the word.
        #
        # NOT `line_end`: it swallows a trailing semicolon, and mmdc draws
        # `graph TD;click;B` as two nodes.
        #
        # A comment is not one of the endings either. Behind a word it is
        # not a comment at all, because mermaid only strips one at the
        # start of a line: mmdc reads `href%%c` as a SINGLE node.
        #
        # The end of the source IS one. Mermaid appends a newline before it
        # lexes, so a word at the very end is followed by one after all.
        #
        # These three words also guard an id, which is why `node_keyword`
        # reaches for this rule rather than restating it.
        rule(:spaced_keyword) do
          (str('click') | str('href') | str('call')) >>
            (space | newline | eof).present?
        end

        # mermaid's link targets, as they appear at the END of a click
        # action (`click A "url" "_blank"`). They are reserved as node ids
        # too, but that is `RESERVED_WORDS`' job now — this rule is only
        # the click-action tail, which is why it survives on its own.
        rule(:link_target) do
          (str('_parent') | str('_blank') | str('_self') | str('_top')) >>
            word_boundary
        end

        # A word ends where the next character cannot continue it, and
        # mermaid counts an accent as the end: `1endé` is refused while
        # `1end_`, `1end2` and `1endx` are all ids.
        rule(:word_boundary) { match['a-zA-Z0-9_'].absent? }

        # One `x` or `o` and then a link body, with nothing between them.
        rule(:flush_link_marker) { match['xo'] >> link_body }

        # Node with optional shape and edges
        rule(:node_edge_statement) do
          reserved_keyword.absent? >>
            node_with_shape.as(:node) >>
            (ws? >> edge_chain).maybe.as(:edges) >>
            loose_statement_end
        end

        # Standalone node (just an identifier)
        rule(:standalone_node) do
          reserved_keyword.absent? >> node_id.as(:node_id) >>
            loose_statement_end
        end

        # Node with its optional shape, inline class and metadata.
        # Every optional part is captured whether or not it is present, so
        # the tree has one shape instead of one per combination. Parslet
        # omits a `.maybe` that wraps its own `.as`, which is why the
        # transform previously needed a rule per combination.
        # On its second branch the `:shape` slot comes back nil:
        # `dot_absent` is a zero-width lookahead and captures nothing. It
        # is there only to refuse the flush dot a bare name would
        # otherwise swallow.
        #
        # The shape opening abuts the id, with no gap of any kind: mmdc
        # refuses `A [B]`, `A\t[B]`, `A\n[B]` and `A %% c\n[B]` alike.
        #
        # `flush_link_marker.absent?` on the first line is the other
        # refusal. A lone `x` or `o` sitting flush against a link body is
        # mermaid's link-START marker, not a node called `x`: mmdc reads
        # `x===B` as a link with nothing on its left and refuses it, while
        # it draws `xx===B` and `x === B` — the marker has to be one
        # character and flush. This rule is the edge TARGET as well as the
        # statement's own node, so the guard governs both positions, and
        # mmdc refuses `A --> x---B` for the same reason it refuses
        # `x===B`.
        rule(:node_with_shape) do
          flush_link_marker.absent? >>
            node_id.as(:node_id) >>
            (node_shape.as(:shape) | dot_absent.as(:shape)) >>
            (inline_class >> dot_absent).maybe.as(:inline_class) >>
            node_metadata.maybe.as(:metadata)
        end

        # A shape and a `@{...}` block each close the node's name, and a
        # link may then sit flush against it: mmdc draws `A[x].-B` and
        # `A@{ shape: rect }.->B`. A bare name is still growing, and so is
        # the class name of `A:::c` — each takes a `.` in mermaid, so mmdc
        # reads the dot of `A.-B` and of `A[x]:::c.-B` as name text and
        # refuses `A.->B`, `A:::c.->B` and `A[x]:::c.->B` outright.
        #
        # `node_id` carries a dot the same way a bare name does — see its
        # own comment above — so `A.-B` reads exactly as mmdc reads it,
        # as the single node `"A.-B"`, not a link: that is the no-shape
        # fallback above, where `dot_absent` stands in for `:shape`
        # itself. A real shape bypasses the guard outright — `A[x].-B`
        # and `A@{ shape: rect }.->B` both draw as mmdc draws them —
        # unless an inline class follows the shape, which is the second
        # place the guard runs. That second use is where Sirena and mmdc
        # part ways: the other five — `A:::c.-B`, `A[x]:::c.-B` and the
        # three `.->` forms — are still refused rather than read as a
        # link.
        rule(:dot_absent) { str('.').absent? }

        # `D@{ shape: rounded, label: "DD" }` — mermaid's newer way of
        # giving a node a shape or a label, usable as a statement of its own
        # or as a suffix inside an edge chain.
        # The body is captured raw and handed to YAML, because that is what
        # mermaid does with it. A single-line body is a flow mapping and a
        # multiline one is block YAML, so commas are required on one line
        # and rejected across several — a grammar rule cannot express that
        # without reimplementing YAML badly.
        rule(:node_metadata) do
          str('@{') >> metadata_body.as(:body) >> str('}')
        end

        # An unmatched `"` is not body text. mermaid's lexer stays in its
        # string state to the end of the block and refuses the source;
        # falling through to the generic branch took `A@{ label: a"b }`,
        # which mmdc rejects.
        #
        # A caret is not body text either. mermaid takes the run between
        # the braces with `[^}^"]+`, so a `^` outside a quoted value ends
        # the block early and mmdc refuses `A@{ label: a^b }`. Inside the
        # quotes the rule is `[^"]+`, and `A@{ label: "a^b" }` draws.
        rule(:metadata_body) do
          (metadata_comment_line | metadata_quoted |
            (metadata_stop.absent? >> any)).repeat
        end

        rule(:metadata_stop) { str('"') | str('}') | str('^') }

        # Mermaid strips comments before lexing, so their stops are text.
        # `line_space` rather than Ruby's `\s`: the indent has to be the set
        # mmdc calls whitespace, or a comment indented with a no-break space
        # keeps its `%%` in the label and its `}` closes the block.
        #
        # `%%{` opens a directive rather than a comment and is left alone,
        # which is what makes sirena refuse `A@{ shape: rect` nl `%%{ x }`
        # nl `}` the way mmdc does.
        rule(:metadata_comment_line) do
          newline >> line_space.repeat >> str('%%') >> str('{').absent? >>
            (newline.absent? >> any).repeat(1)
        end

        # A double-quoted run is skipped whole so a brace inside it is
        # text. Only the double quote does this: mermaid's metadata lexer
        # has one string state and `"` opens it, so `label: 'a}b'` ends the
        # block at that brace and mmdc rejects the line.
        # A comment line inside the quotes is skipped first, because the
        # quote that closes this run cannot be one mermaid already deleted:
        # `label: "one` nl `%% has " quote` nl `two"` is one label to mmdc.
        rule(:metadata_quoted) do
          str('"') >>
            (metadata_comment_line | (str('"').absent? >> any)).repeat >>
            str('"')
        end

        # Inline class syntax: :::className
        rule(:inline_class) do
          str(':::') >> identifier
        end

        # Node shape with label
        rule(:node_shape) do
          # Order matters: try longer delimiters first
          shape_triple_circle |
            shape_stadium |
            shape_subroutine |
            shape_cylindrical |
            shape_double_circle |
            shape_hexagon |
            shape_parallelogram |
            shape_parallelogram_alt |
            shape_trapezoid |
            shape_trapezoid_alt |
            shape_asymmetric |
            shape_rectangle |
            shape_rounded |
            shape_rhombus
        end

        # Shape definitions (15+ shapes)
        # Rectangle: [label]
        rule(:shape_rectangle) do
          lbracket.as(:open) >>
            (rbracket.absent? >> any).repeat.as(:label) >>
            rbracket.as(:close)
        end

        # Rounded: (label)
        rule(:shape_rounded) do
          lparen.as(:open) >>
            (rparen.absent? >> any).repeat.as(:label) >>
            rparen.as(:close)
        end

        # Stadium: ([label])
        rule(:shape_stadium) do
          str('([').as(:open) >>
            (str('])').absent? >> any).repeat.as(:label) >>
            str('])').as(:close)
        end

        # Subroutine: [[label]]
        rule(:shape_subroutine) do
          str('[[').as(:open) >>
            (str(']]').absent? >> any).repeat.as(:label) >>
            str(']]').as(:close)
        end

        # Cylindrical/Database: [(label)]
        rule(:shape_cylindrical) do
          str('[(').as(:open) >>
            (str(')]').absent? >> any).repeat.as(:label) >>
            str(')]').as(:close)
        end

        # Circle: ((label))
        rule(:shape_double_circle) do
          str('((').as(:open) >>
            (str('))').absent? >> any).repeat.as(:label) >>
            str('))').as(:close)
        end

        # Triple Circle: (((label)))
        rule(:shape_triple_circle) do
          str('(((').as(:open) >>
            (str(')))').absent? >> any).repeat.as(:label) >>
            str(')))').as(:close)
        end

        # Asymmetric: >label]
        rule(:shape_asymmetric) do
          str('>').as(:open) >>
            (rbracket.absent? >> any).repeat.as(:label) >>
            rbracket.as(:close)
        end

        # Rhombus/Diamond: {label}
        rule(:shape_rhombus) do
          lbrace.as(:open) >>
            (rbrace.absent? >> any).repeat.as(:label) >>
            rbrace.as(:close)
        end

        # Hexagon: {{label}}
        rule(:shape_hexagon) do
          str('{{').as(:open) >>
            (str('}}').absent? >> any).repeat.as(:label) >>
            str('}}').as(:close)
        end

        # Parallelogram: [/label/]
        rule(:shape_parallelogram) do
          str('[/').as(:open) >>
            (str('/]').absent? >> any).repeat.as(:label) >>
            str('/]').as(:close)
        end

        # Parallelogram Alt: [\label\]
        rule(:shape_parallelogram_alt) do
          str('[\\').as(:open) >>
            (str('\\]').absent? >> any).repeat.as(:label) >>
            str('\\]').as(:close)
        end

        # Trapezoid: [/label\]
        rule(:shape_trapezoid) do
          str('[/').as(:open) >>
            (str('\\]').absent? >> any).repeat.as(:label) >>
            str('\\]').as(:close)
        end

        # Trapezoid Alt: [\label/]
        rule(:shape_trapezoid_alt) do
          str('[\\').as(:open) >>
            (str('/]').absent? >> any).repeat.as(:label) >>
            str('/]').as(:close)
        end

        # Edge chain: can have multiple edges from one node
        rule(:edge_chain) do
          edge >> (ws? >> edge).repeat
        end

        # Single edge with optional label
        rule(:edge) do
          arrow.as(:arrow) >>
            ws? >>
            edge_label.maybe.as(:label) >>
            ws? >>
            reserved_keyword.absent? >> node_with_shape.as(:target)
        end

        # Link forms
        # Every symbol-only link mermaid draws, probed one at a time
        # against mmdc rather than counted from the docs. The form that
        # carries its label in the middle — `A -- text --> B` — is a
        # different shape and is still refused; see the spec that pins it.
        #
        # `->` and `==` are deliberately absent: sirena accepted both and
        # mermaid rejects them.
        # `~` never opens a visible link, so this alternation is
        # mutually exclusive and its order is free.
        rule(:arrow) do
          (invisible_link | visible_link).as(:token)
        end

        # `~~~` takes no markers at all. mmdc rejects `~~~>` outright, and
        # it never reads an `o` or an `x` beside a tilde run as a marker
        # either — `A o~~~o B` is refused, and written flush `Ao~~~oB` is
        # DRAWN, as the two nodes `Ao` and `oB` with an invisible link
        # between them. Sirena gives both the same answers.
        rule(:invisible_link) { str('~~~') >> str('~').repeat }

        # The vocabulary is generated, not listed. Enumerating it missed
        # forms mmdc renders — `====`, `-.-x`, `<--x`, `o----o` among them
        # — and got `o--x` wrong on top of that.
        #
        # A leading marker is taken here whatever it is; whether mermaid
        # honours it depends on the marker at the other end, which the
        # transform decides.
        #
        # Headed first: parslet's alternation takes the first branch that
        # matches, and `long_link` would swallow the `---` of `--->` and
        # leave the `>` for the target to start with, which nothing can
        # parse — the whole diagram would be thrown away.
        rule(:visible_link) { link_start.maybe >> (headed_link | long_link) }

        rule(:link_start) { match['ox<'] }
        rule(:link_end) { match['>xo'] }

        rule(:headed_link) { link_body >> link_end }

        # The three bodies part on a `-`, an `=`, or a dot no other body
        # carries — a dotted one may open with the dot itself — so this
        # alternation is mutually exclusive and its order is free. Only
        # the one above is load-bearing.
        rule(:link_body) { solid_body | thick_body | dotted_body }

        rule(:solid_body) { str('--') >> str('-').repeat }
        rule(:thick_body) { str('==') >> str('=').repeat }

        # The opening hyphen is optional. mmdc draws `.-`, `..->` and
        # `<.-x` exactly as it draws `-.-`, `-..->` and `<-.-x`, and this
        # rule refused the whole leading-dot half of the family.
        rule(:dotted_body) { str('-').maybe >> str('.').repeat(1) >> str('-') }

        # Without a marker the body has to be longer than its minimum:
        # mmdc draws `---` and `===` and refuses `--` and `==`. A dotted
        # body carries a dot already, so its own minimum — `.-` — is a
        # link on its own and it stands here unchanged.
        rule(:long_link) { long_solid | long_thick | dotted_body }
        rule(:long_solid) { str('---') >> str('-').repeat }
        rule(:long_thick) { str('===') >> str('=').repeat }

        # Edge label: can be in pipes |label|
        rule(:edge_label) do
          pipe_label
        end

        # Pipe label: |label|
        rule(:pipe_label) do
          pipe >> (pipe.absent? >> any).repeat(1) >> pipe
        end

        # A subgraph is NAMED, not built. It takes a quoted string and the
        # keyword `end`, but not the other reserved words — mmdc draws
        # `subgraph end [Title]` and `subgraph "AB" [Title]` and refuses
        # `subgraph default [Title]` and `subgraph _self [Title]`.
        #
        # `quoted_run`, not `quoted_string`: the shared rule takes an EMPTY
        # body and wraps it in its own `.as(:string)`, while mmdc refuses
        # `subgraph ""` and draws `subgraph " "`.
        #
        # An empty pair of quotes names nothing ON ITS OWN but may stand in
        # FRONT of a name, so `subgraph "" A` and `subgraph ""A` both draw.
        # Whitespace between the pair and the name is optional, so the name
        # is taken here rather than left to `subgraph_trailing_name`, which
        # only starts at a space.
        rule(:subgraph_id) do
          subgraph_quoted_name |
            (str('""') >> space.repeat >> subgraph_name_word) |
            subgraph_name_word
        end

        # `quoted_run`'s body, captured. The quotes are not part of the
        # name: the transform compares ids and builds the title from this
        # text, so `subgraph "a b"` has to arrive as `a b`. Never empty,
        # for the same reason `quoted_run` is not.
        rule(:subgraph_quoted_name) do
          str('"') >> (str('"').absent? >> any).repeat(1).as(:string) >>
            str('"')
        end

        # A name that hunts up an `end` and then ends the line closes the
        # subgraph on the spot. mermaid lexes `end\b\s*` as its END token,
        # so `subgraph end` opens nothing and the body's own `end` is left
        # over. mmdc refuses it, and refuses `subgraph ""end`,
        # `subgraph 1end` and `subgraph éend` the same way, while
        # `subgraph Zend`, `subgraph endx` and `subgraph Z#end` draw.
        #
        # Anything but whitespace after the name calls it off — a title,
        # another word, or a `;` — so `subgraph end [T]`, `subgraph end A`
        # and `subgraph end;` all draw. Whitespace does not save it in any
        # mixture, which is mermaid's own `end\b\s*` eating the run. The
        # run is `line_space`, so a no-break space goes with the keyword
        # the way a plain one does.
        #
        # The whole condition goes INSIDE the walk. Hunting the word alone
        # and testing the line end behind it commits to the FIRST `end` and
        # PEG never resumes at a later one, so `subgraph A endéend` would be
        # taken as a name where mmdc refuses it. `subgraph A endéend [T]`
        # still draws: with a title behind it no `end` ends the line.
        rule(:bare_subgraph_end) do
          token_at_lexer_restart(
            subgraph_end_word >> line_space.repeat >> (newline | eof)
          )
        end

        # The `end` guard belongs here because every subgraph word funnels
        # through this rule — both arms of `subgraph_id` and every
        # trailing word — so `subgraph end`, `subgraph ""end` and
        # `subgraph A end` are refused by the same line.
        #
        # A subgraph keyword and a link opening end a name the same way
        # they end a node id, and mermaid looks for both behind every
        # lexer restart. So `subgraph 1default [T]`, `subgraph #Zédefault
        # [T]` and `subgraph Zé.- [T]` are refused, while `subgraph #end
        # [T]` and `subgraph a.- [T]` draw. Without the link guard all
        # sixteen measured refusals parsed here.
        rule(:subgraph_name_word) do
          bare_subgraph_end.absent? >>
            token_at_lexer_restart(subgraph_keyword).absent? >>
            dot_run_before_link.absent? >>
            token_at_lexer_restart(arrowhead_open).absent? >>
            id_run
        end

        rule(:subgraph_reserved) do
          SUBGRAPH_RESERVED.map { |word| str(word) }.reduce(:|) >>
            word_boundary
        end

        # All three directive words are reserved here too, and they end a
        # word the same way they do in a node id — `subgraph click- [T]`
        # and `subgraph clickx [T]` are ordinary names.
        #
        # `click` looked like the exception and is not. mmdc draws
        # `subgraph click [T]` only while the body holds no link: mermaid
        # opens its click state on the word and swallows the title, so the
        # subgraph is anonymous and the next link is a parse error. Probing
        # with a bare `X` inside hid that; `X --> Y` shows it.
        rule(:subgraph_keyword) { subgraph_reserved | spaced_keyword }

        # A click target is named, not built, and mermaid is at its most
        # permissive here: `click default`, `click _self` and `click end`
        # all render, and so does `click --> "url"`. The target is simply
        # everything up to the next space, tab or newline. Only a leading
        # quote is out — mmdc refuses `click "AB" "https://example.com"`
        # because the quote opens a string instead.
        #
        # The terminator is this grammar's own whitespace, not Ruby's `\s`.
        # `\s` holds a vertical tab and a form feed, and ending the target
        # on either refused `click A\vB "url"` and `click A\fB "url"`,
        # which mmdc draws. It stays aligned with the single `space` in
        # `click_statement` that holds the action off the target.
        rule(:click_target) do
          str('"').absent? >> ((space | newline).absent? >> any).repeat(1)
        end

        # A node id is a bare word, never a quoted run. It is BUILT here,
        # so every guard applies and malformed ids cannot bypass them.
        #
        # Mermaid's node ids are far wider than a programming identifier:
        # they may lead with a digit (`1-->2`), and carry dots, slashes and
        # hyphens (`9e122290`, `a.b`, `a/b`, `a-b`).
        #
        # A hyphen is only part of the id when an arrow cannot start there,
        # so `a-b` is one node while `a-->b` stays two.
        #
        # Mermaid does not stop hunting for a keyword at the start of an
        # id, so a reserved word buried in one is still a keyword there,
        # and the places it looks again are positions, not characters:
        # `#end` `1end` `éend` are refused, `Z#end` `Z1end` `$end` draw.
        rule(:node_id) do
          id_before_xo_link |
            (token_at_lexer_restart(node_keyword).absent? >>
              dot_run_before_link.absent? >>
              arrowhead_dot_dash.absent? >> id_run)
        end

        # A node id ends before one `x` or `o` when `--`, `==` or `-.`
        # follows. A doubled `x`/`o`, as in `1xx`, keeps the marker in the
        # id, and so does a settled character in front of it — `Zx-->B` and
        # `A1x-->B` are one node and a plain link.
        #
        # Where the marker splits the id is a lexer restart, so the walk is
        # the same one every other guard here runs. mmdc splits `#x-->B`
        # into `#` and `B`, `&x---B` into `&` and `B`, and `éx-->B`,
        # `中o===B` and `Zéo==>B` the same way.
        #
        # `repeat(1)` rather than `token_at_lexer_restart`'s `repeat`: at
        # zero restarts the marker stands at the id START, where mermaid
        # has no node in front of the link at all. `x-->B` is that shape
        # and it is left exactly where it was.
        #
        # The split link now parses too: `#x-->B` draws `#` and `B`
        # joined by a plain `arrow`, same as mmdc. `Transforms::Flowchart
        # .link_type` is what reads the marker — it honours a leading
        # `x`/`o` only when the trailing one matches it, so a lone
        # leading marker like this one falls back to the head it finds
        # at the other end rather than failing the statement.
        rule(:id_before_xo_link) do
          (xo_link_open.absent? >> restart_step).repeat(1) >>
            xo_link_open.present?
        end

        # The opening of a link that carries a crossed or circled head.
        # Mermaid spells the head on both ends of all three links —
        # `[xo<]?--+[-xo>]`, `[xo<]?==+[=xo>]`, `[xo<]?-?\.+-[xo>]?` — so
        # the marker leads a dash, an equals or a dotted run alike.
        #
        # The dotted one puts its dash BEFORE the dots and makes it
        # optional, so it opens as `x-.` and as `x.-` both.
        # `arrowhead_open` already spells the whole opening, markers and
        # leading dash included, so it is reused rather than respelt.
        #
        # A settled character in front kills the opening, which is what
        # mmdc does too: `Zéax.-B`, `x1.-` and `xx.-` keep their whole id
        # while `#x.-B` and `éx.-B` are refused.
        rule(:xo_link_open) do
          arrowhead_open |
            (match['xo'] >> (str('--') | str('==') | str('-.')))
        end

        # A hyphen joins the id unless another dash or a dot follows, which
        # is where a link starts. `x`, `o` and `>` are NOT excluded,
        # because mermaid renders `a-o-->B` and `a-x-->B`. `A->B` fails
        # because the hyphen joins the id here and `>B` cannot continue a
        # statement — not because `->` is unknown; `A -> B` is refused by
        # `visible_link`, which spells its shortest solid body `--`.
        rule(:id_hyphen) { str('-') >> match['-.'].absent? }

        rule(:reserved_word) do
          RESERVED_WORDS.map { |word| str(word) }.reduce(:|) >> word_boundary
        end

        rule(:node_keyword) { reserved_word | spaced_keyword }

        # An arrowhead opening standing AT one of these places is a link,
        # and mermaid starts a fresh token behind it — so the walk has to
        # carry on past it, or it stalls on the `x.-` and never sees the
        # word behind it. mmdc refuses `#x.-end --- Z` and `1x.-end --- Z`.
        #
        # Only at one of the places, though. A settled character in front
        # still kills it, so `Zéax.-end` and `Zx.-end` stay whole ids,
        # which is what mmdc draws.
        rule(:restart_step) do
          arrowhead_open | (settled_run.maybe >> restart_run)
        end

        rule(:restart_run) { (id_carry_char | id_restart_char).repeat(1) }

        rule(:settled_run) do
          settled_char >> (settled_char | id_carry_char).repeat
        end

        rule(:settled_char) { id_dot | id_hyphen | id_ascii_char }

        # A dot run against a dash is the opening of a dotted link, not a
        # node: mmdc refuses `.-->B` while `. --> B` is a node called `.`.
        # An equals sign is a different story — `.==>B` renders as `.` and
        # `B`, so excluding it here refused a diagram mermaid draws.
        #
        # Mermaid finds that opening wherever its lexer restarts, not only
        # at the id start, so it is hunted the way a keyword is. `1.-->B`
        # `#.-->B` `Zé.-->B` and `xé.-->B` are all refused, while
        # `Z1.-->B` `Z#.-->B` and `Zéa.-->B` draw as a node and a link.
        #
        # Nothing about what follows changes it. mmdc draws `1.-a --- Z`
        # as THREE nodes — `1`, `a` and the target — because `.-` opened a
        # dotted link between the first two. `dotted_body` does now spell
        # that opening, so the gap is no longer in the vocabulary: it is
        # this rule, which stops the id at the dot run rather than let it
        # start a link, and `1.-a --- Z` is still refused where the
        # spaced `1 .- a --- Z` draws all three. The id stopping short is
        # better than drawing a node that is not on mermaid's page, so the
        # refusal stands until the restart itself is modelled.
        #
        # `arrowhead_dot_dash` below keeps the id in the same spot but is
        # the weaker of the two: it treats the opening as a link only when
        # nothing follows it. What actually stops `#x.-B` is
        # `id_before_xo_link`.
        rule(:dot_run_before_link) { token_at_lexer_restart(dotted_link_open) }

        # `arrowhead_open` without its leading marker. Mermaid's dotted
        # link also carries a trailing `[xo>]`, and it is deliberately NOT
        # spelled here: the tail is optional, so a rule holding it succeeds
        # exactly where one without it does, and the only reader
        # (`dot_run_before_link`) is consumed under `.absent?`, where the
        # length never matters either.
        rule(:dotted_link_open) { str('.').repeat(1) >> str('-') }

        # Everywhere else a dot just joins, dash or no dash: mmdc draws
        # `A.-->B` as `A.` and `B`, and draws `A.-` `A.-B` `A..-->B` and
        # `y.- --> Z`.
        rule(:id_dot) { str('.') }

        # Reads mermaid's dotted left-arrowhead opening — the whole of it,
        # as `arrowhead_open` spells it out below — as a link instead of an
        # id. Where that opening is legal decides the guard.
        #
        # At the id start nothing sits in front of the link, so mermaid
        # always refuses: `x.-`, `x..-`, `x.-z` and `x.-B` all fail. Behind
        # a lexer restart a node does sit in front, so mermaid opens a real
        # link there and reads THREE nodes — `#x.-B --- Z` is `#`, `B` and
        # `Z`. This rule alone would let the id carry on past the opening;
        # `id_before_xo_link` is what stops it at the restart.
        #
        # A settled character in front kills it either way, so `X.-`,
        # `x1.-`, `xx.-` and `xo.-` stay ordinary ids.
        #
        # The second arm needs no "at least one restart" of its own: at
        # zero restarts the arm in front already matches everything
        # `arrowhead_ends_id` could.
        rule(:arrowhead_dot_dash) do
          arrowhead_open | token_at_lexer_restart(arrowhead_ends_id)
        end

        # Copied from the shape of mermaid's own dotted-link rule. In
        # mmdc 11.12.0's flow lexer that rule is
        # `/^(?:\s*[xo<]?-?\.+-[xo>]?\s*)/`, so the opening carries a
        # marker on BOTH ends and may put a dash in front of the dots.
        # Spelling only the middle of it reads `x.-x` as `x.-` plus a stray
        # `x` and restarts every guard downstream one character early.
        #
        # `<` is in mermaid's leading set too and is left out on purpose:
        # it is not an id character here, so it can never be reached
        # inside one.
        rule(:arrowhead_open) do
          (str('x') | str('o')) >> str('-').maybe >> str('.').repeat(1) >>
            str('-') >> match['xo>'].maybe
        end

        # An arrowhead opening with nothing after it that could continue an
        # id. The crossed and circled links this opens ARE drawn — `x--x`,
        # `x-.-x` and the rest parse into real edges, see
        # `Transforms::Flowchart.link_type` — so this rule refuses nothing
        # on its own; it only decides where the id ends. `id_before_xo_link`
        # above is what actually stops the id at the restart.
        rule(:arrowhead_ends_id) { arrowhead_open >> id_body.absent? }

        # Mermaid's lexer spells its id charset out, so an id is not
        # "anything that is not punctuation". It is printable ASCII, or a
        # letter in the basic plane. Category and plane both matter: `é`,
        # `中`, `ª` and `Ａ` draw, while `Ⅰ` (category Nl, not a letter),
        # astral `𝐀`, control characters, combining marks, non-ASCII
        # digits, braille and box drawing are all refused.
        #
        # `\p{L}` is close but not exact, so the letters come from
        # mermaid's own table instead (`MERMAID_UNICODE_TEXT`). How the
        # two differ, and why the table is copied rather than approximated,
        # is written down once beside the table in
        # `grammars/mermaid_unicode_text.rb`.
        #
        # `:` `,` `"` and `%` are printable ASCII and mermaid joins them —
        # it draws `A:B`, `A,B`, `A"B` and `A%B` as single nodes — but they
        # are held back on purpose, because each also opens something else
        # here: an inline class, a declaration list, a quoted label and a
        # comment. Letting them in needs those boundaries worked out first,
        # so it is left for its own change. A `;` is NOT one of them:
        # mermaid separates on it, and `A;B --- Z` draws `A` and then
        # `B --- Z`. mmdc refuses `( ) < = > @ [ ] ^ { | } ~` outright.
        #
        # `-` and `.` are excluded here and handled by their own rules: a
        # hyphen only joins when a link cannot start there.
        #
        # The class is written as three pieces because `restart_step` has
        # to tell them apart. An id itself takes any of the three.
        rule(:id_char) { id_ascii_char | id_carry_char | id_restart_char }

        rule(:id_ascii_char) do
          match['[\\u0021-\\u007E]&&[^;:,"%()<=>@\\[\\]^{|}~.\\-#&*0-9]']
        end

        # These carry mermaid's keyword hunt along rather than ending it.
        rule(:id_carry_char) { match['#&*0-9'] }

        # And a letter outside ASCII starts it over.
        rule(:id_restart_char) { match[MERMAID_UNICODE_TEXT] }

        # An id stops in front of an entity escape, and the guard belongs
        # to the RUN rather than to the character. `arrowhead_ends_id` also
        # reads `id_body`, but it asks a different question — whether
        # anything could continue an id behind a link opening — and there a
        # `#` still could. Guarding the character would change that rule
        # too, so the guard sits here.
        rule(:id_run) { (entity_escape.absent? >> id_body).repeat(1) }

        rule(:id_body) { id_dot | id_hyphen | id_char }

        # Before mermaid lexes anything it rewrites the whole source. The
        # rewrite that matters here is the last of `encodeEntities`' three,
        # `r.replace(/#\w+;/g, …)`, which turns `#\w+;` into a placeholder
        # standing for `&…;`
        # (`mermaid/dist/chunks/mermaid.esm.min/chunk-7CWYLC5S.mjs`). The
        # placeholder is spelt in characters no id may hold, so an id that
        # swallowed the sequence is one mermaid cannot lex.
        #
        # NOT every `#\w+;`, though, and this rule does not model the
        # difference. Two rewrites run FIRST — `/style.*:\S*#.*;/` and
        # `/classDef.*:\S*#.*;/` — and each strips the final `;` from what
        # it matches, so mmdc draws `stylex[foo:#bar]-->A#a;` where this
        # refuses it. Modelling that needs a source pre-pass, which this
        # grammar has no place for yet.
        #
        # The shape is exact: the run must be `[A-Za-z0-9_]` and the `;`
        # must abut it. mmdc refuses `#a;B`, `#35;B` and `Z#a;B`, and draws
        # `#;B`, `#a ;B`, `#é;B` and `#a.b;B` — none of which the rewrite
        # matches.
        #
        # Only the id stops here. mermaid applies the rewrite everywhere,
        # so `A[#a;]` draws a node labelled `&a;`, and rendering that text
        # belongs to a change that models the escape rather than refuses it.
        rule(:entity_escape) do
          str('#') >> match['a-zA-Z0-9_'].repeat(1) >> semicolon
        end

        # Line terminator. A statement ends at the newline, and NOT at a
        # `%%` on the way to it: mermaid strips a comment with
        # `/^\s*%%(?!{)[^\n]+\n?/gm`, anchored to the line start, so a `%%`
        # with a statement in front of it is never a comment. It is content,
        # and mmdc reads `A%%c` as one node called `A%%c` and `A;%%c` as the
        # two nodes `A` and `%%c`.
        #
        # So no trailing comment is taken here. mmdc refuses `A %% c`,
        # `A --> B %% c` and `A[T] %% c` outright.
        #
        # `A%%c` is the one under-acceptance left, and closing it means
        # letting `%` into a node id — a widening this PR does not make.
        # `A;%% c` is refused by `separator`, which is where the `%%` guard
        # lives.
        rule(:line_end) { semicolon.maybe >> space? >> (newline | eof) }
      end
    end
  end
end
