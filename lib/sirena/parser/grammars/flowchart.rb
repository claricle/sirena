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
        # node ids even though the characters are legal. Writing W for any
        # word in the list: the examples pin `W-->Z` and `1W --> Z`, while
        # `W[L]` and `W.foo-->Z` were measured too and are not asserted
        # here. mmdc refuses all four for every word.
        #
        # `direction`, `accTitle`, `accDescr`, `default` and `callback` are
        # NOT among them — mmdc draws `default-->Z`. `href`, `call` and
        # `click` are keywords too but end a word differently, so they live
        # in `spaced_keyword` instead.
        #
        # Taking `direction` as a node id does not bring the statement with
        # it: `direction TB` on its own line is still unparsed here, and
        # mmdc draws it.
        #
        # Longest first, because Parslet does not backtrack into an
        # alternative that already matched: `class` ahead of `classDef`
        # would take the first five characters and then fail the boundary.
        RESERVED_WORDS = %w[
          swimlane-beta interpolate flowchart linkStyle subgraph classDef
          _parent _blank _self graph style class _top end
        ].freeze

        # NOT derived from the node list. A statement keyword is plain text
        # in a subgraph id (`subgraph graph [T]` renders), so every one of
        # those drops out. `default` is reserved here and nowhere else
        # (`subgraph default [T]` does not render, `default-->Z` does).
        # What is left is `default`, plus the five words `linkStyle` takes
        # that both positions share: `interpolate` and the four link
        # targets `_parent`, `_blank`, `_self` and `_top`.
        # Every word in both lists was probed in all three positions.
        #
        # This list happens to have no prefix collisions.
        SUBGRAPH_RESERVED = %w[
          interpolate _parent default _blank _self _top
        ].freeze

        # Mermaid restarts its lexer at certain characters and looks for the
        # target again behind each restart. Six rules walk that path, so
        # they share it here.
        #
        # A `repeat` rather than a recursive rule: a rule that called
        # itself blew the Ruby stack on a 2000-character id, and mmdc
        # draws that id.
        def hunt(target)
          (target.absent? >> restart_step).repeat >> target
        end
        private :hunt

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
        # ordinary. `space?` never crosses a newline, so the guard only
        # fires on the same-line form.
        rule(:separator) do
          (semicolon >> space?).repeat(1) >> str('%%').absent?
        end

        # Node statements tolerate a space before the separator, because the
        # corpus has `graph TD;A ;` and friends. The header and a class
        # assignment do not: mmdc rejects `graph TD ;A` and
        # `class A foo ;B`, so a shared loose separator over-accepted both.
        rule(:loose_separator) { space? >> separator }

        rule(:statement_end) { separator | line_end }
        rule(:loose_statement_end) { loose_separator | line_end }

        # mermaid's full set, aliases included: `BR` and `v` are another
        # down, and three arrow glyphs stand in for the words. `v` is a
        # word here, not a glyph — it needs the same gap `TD` does, while
        # `<`, `>` and `^` do not. Reading any of them as a node put a
        # stray `BR` or `v` in the diagram.
        rule(:direction) { (word_direction | glyph_direction).as(:dir_value) }

        rule(:word_direction) do
          str('TD') | str('TB') | str('BT') | str('BR') | str('LR') |
            str('RL') | str('v')
        end

        # These three need no gap after the keyword — mmdc draws `graph<`.
        rule(:glyph_direction) { match['<>^'] }

        rule(:statements) do
          ((separator | statement) >> ws?).repeat(1)
        end

        rule(:statement) do
          accessibility_statement |
            subgraph_statement |
            style_statement |
            class_def_statement |
            class_assignment_statement |
            click_statement |
            node_edge_statement |
            standalone_node
        end

        # `accTitle:` and `accDescr:` carry the text mermaid puts in the
        # SVG's aria attributes. Without them `accDescr { ... }` parsed as a
        # node called accDescr with the block as its label — a silent
        # misparse rather than a failure.
        rule(:accessibility_statement) do
          acc_descr_block | acc_line
        end

        # Mermaid separates the keyword from its delimiter with \s*, which
        # crosses newlines. `space?` does not, so `accTitle:` followed by
        # the text on the next line made a node called Title, and
        # `accDescr` then `{` on its own line made a phantom accDescr node.
        #
        # `ws?` is wrong the other way: it eats comments, so
        # `accTitle: %% comment` skipped the comment and took the FOLLOWING
        # statement as the title. mmdc keeps `%% comment` as the title text
        # and leaves the next line alone, so the gap is whitespace only.
        #
        # The text runs to the PHYSICAL end of the line, not to `line_end`.
        # A `%%` inside a title is ordinary text — mmdc's title for
        # `accTitle: %% c` is `%% c` — and `line_end` carries nothing but
        # spaces to the newline, so reading the title through it would lose
        # every title that has one.
        #
        # The text may be empty. mmdc renders `accTitle:` with nothing
        # after it, and this rejected the whole diagram.
        rule(:acc_line) do
          (str('accTitle') | str('accDescr')).as(:acc_keyword) >>
            acc_gap >> str(':') >> acc_gap >>
            (newline.absent? >> any).repeat.as(:acc_text) >> (newline | eof)
        end

        # Whitespace crosses newlines, and once a newline is crossed a
        # STANDALONE comment line is skipped whole: mmdc reads
        # `accTitle:` newline `%% c` newline `Real` as the title `Real`.
        # A comment on the delimiter's OWN line stays text, which is why
        # the skipping only starts after the first newline — the
        # same-line protection comes from the structure here, not from a
        # narrower rule, and a separate one could not be killed by any
        # mutation.
        rule(:acc_gap) do
          line_space.repeat >>
            (newline >> (line_space | newline | comment).repeat).repeat
        end

        # Whitespace that stays on the line: mermaid's `\s` without the
        # newline. It is wider than a space and a tab, and mmdc reads
        # `accTitle` no-break-space `:` as a title where this used to
        # throw the whole diagram away.
        #
        # No carriage return: the parser folds every one into a newline
        # before the grammar sees it, the way mermaid does.
        #
        # Ruby's `[[:space:]]` is close but it is not the same set, in
        # both directions. It misses U+FEFF, which mmdc treats as a space,
        # and it adds U+0085, which mmdc does not. Spelling the set out
        # keeps the block indent honest too, since a comment line is only
        # stripped when mmdc agrees the leading run is whitespace.
        rule(:line_space) do
          match['\t\v\f \u00A0\u1680' \
            '\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF']
        end

        # Mermaid deletes whole comment LINES before it parses anything,
        # so a `}` inside one does not close a block: `accDescr {` /
        # `text` / `%% }` swallows every line after it.
        #
        # "Line" is what this got wrong, at both ends. It wanted a
        # trailing newline, so a comment at the end of the source was not
        # one — `%% } C --- D` with no final newline fell through to the
        # character branch and that `}` closed the block. It also took a
        # `%%` from the middle of a line, where mermaid anchors the strip
        # to the line start and mmdc closes the block in
        # `accDescr {text %% }`.
        #
        # So a comment starts at a newline and stops at its own line end,
        # leaving that newline behind. The next line claims it, which is
        # how two comment lines in a row both match, and running out of
        # source just ends the repeat.
        rule(:comment_line) do
          newline >> line_space.repeat >> str('%%') >>
            (newline.absent? >> any).repeat
        end

        rule(:acc_block_body) do
          (comment_line | (str('}').absent? >> any)).repeat
        end

        # The block form ends at its closing brace. Requiring a line end
        # after it rejected `accDescr {Desc}A-->B`, which mermaid renders —
        # the statement rule handles what follows.
        #
        # An unterminated block runs to the end of the source rather than
        # failing: mmdc draws `accDescr {Unterminated` and swallows every
        # line after it, so refusing the source lost a diagram it renders.
        rule(:acc_descr_block) do
          str('accDescr').as(:acc_keyword) >> acc_gap >> str('{') >>
            acc_block_body.as(:acc_text) >>
            (str('}') >> line_space.repeat >> semicolon.maybe).maybe
        end

        # Subgraph: subgraph id [title] ... end
        rule(:subgraph_statement) do
          str('subgraph').as(:subgraph_keyword) >> space >>
            subgraph_id.as(:subgraph_id) >>
            subgraph_trailing_name >>
            # A subgraph body must begin on a new physical line. The gap in
            # front of the `;` is the one node statements already tolerate
            # in `loose_separator`: mmdc draws `A ;` `end ;` `endx ;` and
            # `1end ;` as readily as `A;`. A bare `line_end` refused every
            # one, because its own space run sits BEHIND the semicolon and
            # not in front of it.
            #
            # `line_space`, not `space?`: mermaid's lexer eats its whole
            # space set here, so `subgraph A` no-break-space `;` draws.
            line_space.repeat >> line_end >>
            ws? >>
            statements.maybe.as(:subgraph_statements) >>
            ws? >>
            str('end').as(:subgraph_end) >>
            loose_statement_end
        end

        rule(:subgraph_title) do
          lbracket >> (rbracket.absent? >> any).repeat(1) >> rbracket
        end

        # An unbracketed name runs on past the first space: mermaid titles
        # `subgraph 1 abc` "1 abc". Stopping the name at that space left
        # ` abc` on the line and the body swallowed it as a statement, so a
        # node called `abc` appeared that mmdc never draws.
        #
        # Every word carries the same guards as the first one. Reaching for
        # a bare `id_run` here let ten word refusals through, plus the
        # bracketed-title case, because the guards live in `subgraph_id`
        # and not in `id_run`: mmdc refuses
        # `subgraph A interpolate` `subgraph A href` `subgraph A 1default`
        # `subgraph A .-` and `subgraph A x.-b`.
        #
        # The charset is narrower than mermaid's title text, which is why
        # this only consumes id words. mmdc titles `subgraph A B:C` "A B:C"
        # and this refuses it — an under-acceptance left for a change that
        # models mermaid's own `textNoTags` production. Nothing reads the
        # name yet, so the extra words are consumed, not kept.
        #
        # The bracketed title comes AFTER those words, and this is the only
        # rule that reads it: a separate `space >> subgraph_title` arm in
        # front stopped at the first trailing word, so `subgraph A B [T]`
        # and `subgraph A B C [T]` were both refused here while mmdc draws
        # them. One rule for the whole tail keeps the two from disagreeing
        # about where the title may sit.
        #
        # `subgraph A [T] X` stays refused, which mmdc also refuses:
        # nothing may follow the title on the line.
        #
        # A trailing word carries the same guards as the first one, `end`
        # included. What ends a subgraph is `end` with the LINE behind it —
        # the position, not the word — and that is `bare_subgraph_end`'s
        # whole job, which every subgraph word already runs. Guarding a
        # trailing word on the hunted WORD instead refused ten headers
        # mmdc draws, measured one at a time by putting the guard back:
        # `A end [T]` `A 1end [T]` `A B end [T]` `A end A [T]`
        # `A end end [T]` `A B 1end [T]` `A end B` `A end;` `A end ;` and
        # `A endé`.
        #
        # mmdc draws each as ONE cluster holding `end` in its name. With a
        # bracketed title the whole run becomes the cluster id — `A end [T]`
        # is the cluster `A end` titled `T` — and without one the cluster
        # is auto-named `subGraph0` and the run becomes its label, so
        # `A end B` is labelled `A end B`. Read from mmdc 11.12.0's
        # `class="cluster" id=` and from the text inside its
        # `<foreignObject>`, which is where a label actually lives.
        #
        # `subgraph A end` and `subgraph A 1end` stay refused, which is
        # mmdc's verdict too.
        rule(:subgraph_trailing_name) do
          (space.repeat(1) >> subgraph_name_word).repeat >>
            (space.repeat(1) >> subgraph_title.as(:subgraph_title)).maybe
        end

        rule(:subgraph_end_id) { hunt(subgraph_end_word) }

        rule(:subgraph_end_word) { str('end') >> word_boundary }

        # Style: style nodeId fill:#f9f
        rule(:style_statement) do
          str('style').as(:style_keyword) >> space >>
            reserved_keyword.absent? >> node_id.as(:style_target) >>
            (space >> style_property_list).as(:style_props) >>
            statement_end
        end

        # What a `;` does inside a declaration turns on the value, not on the
        # text after it. Measured against mmdc 11.12.0:
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
        # not an edge, so it stops at anything structural.
        #
        # It ends where `line_end` ends and nowhere else. This carried a
        # `comment.maybe` of its own while `line_end` took a trailing
        # comment; once that went, a `%%` here is ordinary declaration text
        # and the arm could not be reached — 0 verdict changes across all
        # 1997 corpus cases, and the suite green without it.
        rule(:hashed_tail) do
          (structural_token.absent? >> declaration_char).repeat >>
            space? >> (newline | eof).present?
        end

        # What mermaid keeps for shapes and edges. It is refused wherever
        # mermaid expects a bare word — in a style declaration after a `#`
        # and in a callback name alike.
        rule(:structural_token) { compound_token | structural_char }

        # Some of what mermaid reserves is longer than one character, and
        # every character in it is legal on its own. Measured against mmdc
        # 11.12.0 in a style tail and in a callback name alike: `B-C`,
        # `B.C` and `B::C` are ordinary text in both, and `B--C`, `B-.C`
        # and `B:::C` are errors in both. Checking one character at a time
        # misses all three.
        rule(:compound_token) { str(':::') | str('--') | str('-.') }

        # The single-character half of the set. Measured one character at
        # a time against mmdc: every other printable ASCII character is
        # fine in both places.
        rule(:structural_char) { match['\\[\\]{}()<>|~@=^'] }

        rule(:declaration_char) do
          line_end.absent? >> semicolon.absent? >> comma.absent? >> any
        end

        # Permissive, exactly as before: mermaid takes `style A red`,
        # `style A fill:` and `style A fill :red`, and requiring
        # `name:value` here rejected all three. One character minimum
        # though — mmdc refuses `style A` with nothing after it.
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
        # takes exactly four shapes here, and anything else is an error, so
        # the action is spelled out rather than scanned to the end of the
        # line. An open-ended scan drew a node from the junk after a good
        # action: `click A "u" nope;B` and `click A "u");B` both left a
        # node B behind, and mmdc refuses both sources.
        #
        # Every gap between these tokens is ONE space or ONE tab. mermaid
        # counts the characters: `click A href  "u"`, `"u"  "tip"`,
        # `"u"  _blank` and `href "u"` with two tabs are all errors. Only
        # inside a `call` is whitespace free-form.
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
        # exits 1 on `click A call cb`. Nothing else can take that line —
        # `bare_token` refuses a reserved word, and `call` before a space
        # is one.
        rule(:call_opener) { str('call') >> callback_gap }

        # mermaid stops caring about line structure inside a callback, so
        # whitespace and comments are ignorable after `call` and again
        # before the `(`. mmdc renders all four of `call cb()`,
        # `call` nl `cb()`, `call cb` nl `()` and `call cb` nl `%% c` nl
        # `()`. Spaces alone left a stray `cb` node on the following line.
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
        # directive fell through to the node rules: `click ;B` produced
        # nodes `click` and `B`, and mmdc rejects the whole source.
        #
        # The same words that end an id end a statement, so this asks
        # `node_keyword` rather than keeping a second list. It used to hold
        # its own, and the two had already drifted apart by
        # `swimlane-beta`. Collapsing them changed nothing observable —
        # measured over 3680 cases, byte for byte — because the two refuse
        # the same words, so it makes no difference which runs first. This
        # guard is the one that runs first: every call site spells
        # `reserved_keyword.absent? >> node_id`. The value of the collapse
        # is that there is now one list to keep right.
        rule(:reserved_keyword) { node_keyword }

        # `click`, `href` and `call` are directive words wherever a space, a
        # newline or the end of input follows, and ordinary node ids before a
        # `;` or a shape. mmdc refuses `href --- B`, `call --- B` and a bare
        # `href`, and draws `href;B` and `href[x]` as nodes — so the
        # reservation hangs off the boundary, not the word. Reserving only
        # `click` let the other two through.
        #
        # NOT `line_end`: it swallows a trailing semicolon, so `click;`
        # read as a directive and `graph TD;click;B` was refused. mmdc
        # draws that as two nodes.
        #
        # A comment is not one of the endings either — and behind a word it
        # is not a comment at all, because mermaid only strips one at the
        # start of a line. mmdc reads `href%%c` as a SINGLE node called
        # `href%%c`, not as the word `href`. Keeping `%%` out of the
        # endings is what stops the word opening a directive; the line is
        # then refused anyway, since `%` is not in a node id here.
        #
        # The end of the source IS one. Mermaid appends a newline before
        # it lexes, so a word at the very end is followed by one after
        # all, and this is the only rule that says so. A second copy of it
        # lived beside the id rules for a while, and this rule masked that
        # copy so completely that deleting the copy's `eof` left every
        # spec green. Deleting it here now fails five.
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
        # `1end_` `1end2` and `1endx` are all ids. Those four forms and
        # refused `1end` are all pinned in the specs.
        rule(:word_boundary) { match['a-zA-Z0-9_'].absent? }

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

        # Node with its optional shape, inline class and metadata
        # Every optional part is captured whether or not it is present, so
        # the tree has one shape instead of one per combination. Parslet
        # omits a `.maybe` that wraps its own `.as`, which is why the
        # transform previously needed a rule per combination.
        #
        # The opening abuts the id, with no gap of any kind. A `ws?` here
        # took a space, a tab, a newline and even a whole comment line
        # between the two, and mmdc refuses every one of them.
        #
        # Measured over 660 cases — six ids (`A` `A1` `1` `12` `é` `a.b`)
        # against nine shape openings and both ends of a link, each with
        # ten gaps: none, one and two spaces, one and two tabs, the two
        # space/tab mixtures, a vertical tab, a form feed and a carriage
        # return. The 66 mmdc
        # draws are exactly the 66 with no gap. `A\n[B]` and `A %% c\n[B]`
        # are refused too, and widening node ids brought `1 [B]` `12 [B]`
        # `é [B]` and `a.b [B]` into the same arm.
        rule(:node_with_shape) do
          node_id.as(:node_id) >>
            node_shape.maybe.as(:shape) >>
            inline_class.maybe.as(:inline_class) >>
            node_metadata.maybe.as(:metadata)
        end

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

        # Arrow types
        rule(:arrow) do
          thick_arrow | dotted_arrow | plain_arrow
        end

        # Bare `==` is not a link (mmdc rejects `A==B`). A thick link has at
        # least two `=` before an arrowhead or at least three without one.
        # The headed arm comes first so its `>` is not left for the target,
        # and that ordering is also why the open arm needs no `>` guard of
        # its own: the headed arm's `repeat(2)` is greedy, so wherever a
        # `>` follows the equals run it has already matched. One was
        # written here anyway and changed no verdict across a 72-case
        # equals sweep or all 331 flowchart corpus cases — the two sibling
        # link rules carry none either.
        #
        # The open arm carries `trailing_xo_marker.absent?` for the same
        # reason the other two links do. Mermaid's thick link is
        # `[xo<]?==+[=xo>]`, so the trailing `x` belongs to the LINK.
        # Without the guard `A===xB` drew `A` and a node called `xB` where
        # mmdc 11.12.0 draws `A` and `B` joined by one crossed-head link,
        # and `A===x` `A===o` `A===x --- Z` and `A====x --- Z` all parsed
        # here while mmdc refuses every one of them.
        rule(:thick_arrow) do
          (str('=').repeat(2) >> str('>') |
            str('=').repeat(3) >> trailing_xo_marker.absent?).as(:thick)
        end

        # A dotted link has one or more dots. As with a plain link, put the
        # headed arm first and guard only the open arm from consuming an
        # unsupported crossed or circled arrowhead.
        rule(:dotted_arrow) do
          (str('-') >> str('.').repeat(1) >> str('->') |
            str('-') >> str('.').repeat(1) >> str('-') >>
              trailing_xo_marker.absent?).as(:dotted)
        end

        # Mermaid's plain link is `--+[-xo>]`: two or more dashes, then
        # ONE of `-`, `x`, `o`, `>`. Spelling it as the two fixed strings
        # `-->` and `---` got the length wrong in both directions —
        # `A----` drew an edge to a node called `-`, `A----B` drew
        # `A --> -B` where mermaid draws `A --> B`, and `A--->B` and
        # `A-----B` were refused outright. The dashes are counted here
        # instead.
        #
        # A bare `->` is NOT a plain link: mmdc refuses `A->B` `A -> B`
        # `A ->B` and `A-> B` alike. Listing it drew an edge for the two
        # spaced forms — an over-acceptance that outlived the `id_hyphen`
        # guard, which only ever closed the unspaced pair.
        #
        # The arrowhead arm goes first because Parslet does not backtrack
        # into an alternative that already matched, and the open arm would
        # otherwise eat the dashes that the `>` needs.
        rule(:plain_arrow) do
          (str('--') >> str('-').repeat >> str('>') |
            str('--') >> str('-').repeat(1) >>
              trailing_xo_marker.absent?).as(:plain)
        end

        # A trailing `x` or `o` belongs to the LINK, not to the node behind
        # it. All three of mermaid's links carry one: the plain link is
        # `[xo<]?--+[-xo>]`, the thick one `[xo<]?==+[=xo>]` and the dotted
        # one `[xo<]?-?\.+-[xo>]?`. So `A---x` and `A===x` are each one
        # link carrying a crossed arrowhead, and `A---x --- Z` and
        # `A===x --- Z` are refused for holding two links with no node
        # between them.
        #
        # Sirena draws no crossed or circled arrowhead, so the marker is
        # REFUSED rather than drawn with the wrong head. The arrowhead-less
        # `===` above was refused for that same reason once; it no longer is,
        # because a headless link now resolves to a type that draws no
        # marker. A crossed or circled head still has no shape to draw.
        # Modelling these heads is the change that also owns `1x-->B`.
        #
        # 56 inputs parsed here that mmdc refuses, and widening node ids
        # is what put 48 of them within reach — `#---x --- Z` `1-.-o --- Z`
        # and `é---x --- Z` among those. The other 8, `A---x --- Z` and
        # its kin, were already reachable and already wrong. Those counts
        # are the plain and dotted families only; `thick_arrow` reached
        # this rule later and brought `A===xB` `A===x` and `A===x --- Z`
        # with it.
        #
        # Only the arrowhead-less forms need the guard: after `-->` or
        # `-.->` mermaid has already closed the link, so the `x` in
        # `A-->x` really is a node.
        rule(:trailing_xo_marker) { match['xo'] }

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
        # `quoted_run`, not `quoted_string`: the shared rule takes an
        # EMPTY body, and mmdc refuses `subgraph ""` while drawing
        # `subgraph " "`. It also wraps what it takes in its own
        # `.as(:string)`, so a quoted name arrived as `{string: "AB"@19}`
        # where a bare one is a plain slice — the same nested-tree shape
        # this file refuses to give `node_id`. This rule is non-empty and
        # captures a slice, so both go away together.
        #
        # An empty pair of quotes still names nothing ON ITS OWN, and it
        # may still stand in FRONT of a name: mmdc refuses `subgraph ""`
        # and draws `subgraph "" A` and `subgraph ""A` alike. Reading only
        # `quoted_run` here refused those two as well, which is more than
        # mermaid does.
        #
        # Whitespace between the pair and the name is optional, so the
        # name is taken here rather than left to `subgraph_trailing_name`,
        # which only starts at a space.
        rule(:subgraph_id) do
          quoted_run | (str('""') >> space.repeat >> subgraph_name_word) |
            subgraph_name_word
        end

        # A name that hunts up an `end` and then ends the line closes the
        # subgraph on the spot. mermaid lexes `end\b\s*` as its END token,
        # so `subgraph end` opens nothing and the body's own `end` is left
        # over — mmdc refuses it, and refuses `subgraph ""end` and
        # `subgraph 1end` the same way.
        #
        # It is the same hunt the trailing words already run, and it lands
        # in the same places: `end` `#end` `1end` `éend` `##end` `1#end`
        # `Zéend` and `ZA中end` are all refused, while `Z#end` `Z1end`
        # `ZéAend` `$end` `_end` `Zend` `endx` `end_` and `end2` all draw.
        # `subgraph end` was refused only as a TRAILING word before this,
        # so the first name let all eight through.
        #
        # Anything but whitespace after the name calls it off — a title,
        # another word, or a `;`. `subgraph end [T]` `subgraph end A`
        # `subgraph end;` `subgraph end ;` and `subgraph end\t;` all draw.
        # Whitespace does not save it, in any mixture: `subgraph end`
        # `end ` `end   ` `end\t` `end\t\t` `end \t` and `end\t ` are all
        # refused, which is mermaid's own `end\b\s*` eating the run.
        #
        # The run is `line_space`, the set this grammar already measured
        # against mermaid's, so a no-break space goes with the keyword the
        # way a plain one does: `subgraph end` no-break-space is refused
        # too, while `subgraph A` no-break-space draws.
        rule(:bare_subgraph_end) do
          subgraph_end_id >> line_space.repeat >> (newline | eof)
        end

        # The `end` guard belongs here because every subgraph word funnels
        # through this rule — both arms of `subgraph_id` and every
        # trailing word — so `subgraph end`, `subgraph ""end` and
        # `subgraph A end` are refused by the same line.
        rule(:subgraph_name_word) do
          bare_subgraph_end.absent? >> subgraph_keyword_id.absent? >>
            dot_run_before_link.absent? >> subgraph_arrowhead.absent? >>
            id_run
        end

        # A link opening ends a subgraph name the same way it ends a node
        # id, and mermaid hunts for it in the same places: mmdc refuses
        # `subgraph .- [T]` `subgraph Zé.- [T]` and `subgraph ...- [T]`,
        # and draws `subgraph a.- [T]` `subgraph .. [T]` and
        # `subgraph Zéa.- [T]`. Without the guard all sixteen refusals
        # parsed here, because a name was hunted for keywords only.
        #
        # The arrowhead half is STRICTER here than in a node id. A node can
        # carry on past the opening when something follows it, so
        # `#x.-B --- Z` is one id — but a subgraph name cannot, and mmdc
        # refuses `subgraph #x.-b [T]`. So this walk fires on the opening
        # itself, with no look at what comes after.
        rule(:subgraph_arrowhead) { hunt(arrowhead_open) }

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

        # A subgraph name is hunted the same way a node id is, with its own
        # words: `subgraph 1default [T]` and `subgraph #Zédefault [T]` are
        # refused, and `subgraph #end [T]` draws because `end` is not one.
        rule(:subgraph_keyword_id) { hunt(subgraph_keyword) }

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
        rule(:node_id) do
          id_before_xo_link |
            (node_keyword_id.absent? >> dot_run_before_link.absent? >>
              arrowhead_dot_dash.absent? >> id_run)
        end

        # Measured against mmdc 11.12.0: a node id ends before one `x` or
        # `o` when `--`, `==` or `-.` follows. A doubled `x`/`o`, as in
        # `1xx`, keeps the marker in the id, and so does a settled
        # character in front of it — `Zx-->B` and `A1x-->B` are one node
        # and a plain link.
        #
        # Where the marker splits the id is a lexer restart, the same walk
        # every other guard here runs, and reading it as a leading run of
        # DIGITS was that walk measured on one prefix shape. mmdc splits
        # `#x-->B` into `#` and `B`, `&x---B` into `&` and `B`, `*o-.-B`
        # into `*` and `B`, and `éx-->B` `中o===B` `#1x-->B` `1#x-->B`
        # `Aéx-->B` and `Zéo==>B` the same way.
        #
        # Measured over 228 sources — 19 prefixes, each with `x` and `o`,
        # against all six link spellings. A digit prefix stopped; nine
        # other prefixes that restart the lexer did not, and 108 of the
        # 228 drew a node mermaid never puts on the page. Walking the
        # restarts takes that to none, with no new over-acceptance.
        #
        # `repeat(1)` rather than `hunt`'s `repeat`: at zero restarts the
        # marker stands at the id START, where mermaid has no node in
        # front of the link at all. `x-->B` is that shape and it is left
        # exactly where it was.
        #
        # Sirena models no `x`/`o` link-start marker at all, so stopping
        # the id makes the statement fail. That is safer than drawing a
        # different graph with `1x` or `#x` as the node.
        rule(:id_before_xo_link) do
          (xo_link_open.absent? >> restart_step).repeat(1) >>
            xo_link_open.present?
        end

        # The opening of a link that carries a crossed or circled head.
        # Mermaid spells the head on both ends of all three links —
        # `[xo<]?--+[-xo>]`, `[xo<]?==+[=xo>]`, `[xo<]?-?\.+-[xo>]?` — so
        # the marker leads a dash, an equals or a dotted run alike.
        rule(:xo_link_open) do
          match['xo'] >> (str('--') | str('==') | str('-.'))
        end

        # A hyphen joins the id unless another dash or a dot follows, which
        # is where a link starts. Excluding `x`, `o` and `>` as well
        # rejected `a-o-->B` and `a-x-->B`, which mermaid renders. `A->B`
        # fails because the hyphen joins the id here and `>B` cannot
        # continue a statement — not because `->` is unknown; it is
        # `plain_arrow` that refuses it, for every spacing.
        rule(:id_hyphen) { str('-') >> match['-.'].absent? }

        rule(:reserved_word) do
          RESERVED_WORDS.map { |word| str(word) }.reduce(:|) >> word_boundary
        end

        rule(:node_keyword) { reserved_word | spaced_keyword }

        # Mermaid does not stop hunting for a keyword at the start of an
        # id, so a reserved word buried in one is still a keyword there.
        # Where it looks again was measured over 1300 cases and it is a
        # position, not a character: `#end` `1end` `éend` `##end` `1#end`
        # `Zéend` and `ZA中end` are all refused, while `Z#end` `Z1end`
        # `#Z#end` `ZéAend` `$end` and `_end` all draw.
        #
        # So the id start is one of those places, a letter outside ASCII
        # makes another, `# & *` and digits carry along whatever came
        # before them, and every other id character settles the hunt.
        #
        # Walk the places one at a time and stop at the first one holding a
        # word.
        rule(:node_keyword_id) { hunt(node_keyword) }

        # An arrowhead opening standing AT one of these places is a link,
        # and mermaid starts a fresh token behind it — so the hunt has to
        # carry on past it. Without that step the walk stalled on the
        # `x.-` and never saw the word behind it, and `#x.-end --- Z`
        # `1x.-end --- Z` and `#x.-1.-->B` all parsed here while mmdc
        # refused them.
        #
        # Only at one of the places, though. A settled character in front
        # still kills it, so `Zéax.-end` `#Zx.-end` and `Zx.-end` stay
        # whole ids, which is what mmdc draws.
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
        # Nothing about what follows changes it. Reading on and firing
        # only ahead of `->` `--` or `=` let `1.-` and `1.-x --- Z`
        # through, and mmdc refuses both. mmdc does draw `1.-a --- Z` —
        # but as THREE nodes, `1`, `a` and the target, because `.-`
        # opened a dotted link between the first two. That opening is the
        # one sirena has no link for — `dotted_arrow` builds `-.-` and
        # `-.->`, not a run that starts on the dot — so the id stops at it
        # instead of swallowing it and drawing a node that is not on
        # mermaid's page.
        #
        # `arrowhead_dot_dash` below keeps the id in the same spot, and
        # the two are not in disagreement: there the opening is only a
        # link when nothing follows it, so an id can carry on past it.
        rule(:dot_run_before_link) { hunt(dotted_link_open) }

        # `arrowhead_open` without its leading marker. Mermaid's dotted
        # link also carries a trailing `[xo>]`, and it is deliberately NOT
        # spelled here: the tail is optional, so a rule holding it succeeds
        # exactly where one without it does, and the only reader
        # (`dot_run_before_link`) is consumed under `.absent?`, where the
        # length never matters either. Writing it changed no verdict across
        # 2761 probe cases and the whole 1997-case corpus — it would be
        # decoration that reads like a guard.
        rule(:dotted_link_open) { str('.').repeat(1) >> str('-') }

        # Everywhere else a dot just joins, dash or no dash: mmdc draws
        # `A.-->B` as `A.` and `B`, and draws `A.-` `A.-B` `A..-->B` and
        # `y.- --> Z`.
        rule(:id_dot) { str('.') }

        # `arrowhead_dot_dash` recognizes mermaid's dotted left-arrowhead
        # opening — the whole of it, as `arrowhead_open` spells it out
        # below, markers and leading dash included — as a link instead of
        # an id. Where that opening is legal decides the guard, and it was
        # measured over 173 cases.
        #
        # At the id start nothing sits in front of the link, so mermaid
        # always refuses: `x.-` `x..-` `x.-z` and `x.-B` all fail. Behind
        # a lexer restart a node does sit in front, so the opening is a
        # real link and only fails when nothing follows it — `#x.- --> Z`
        # is refused while `#x.-B --- Z` draws.
        #
        # A settled character in front kills it either way, so `X.-`
        # `x1.-` `xx.-` and `xo.-` stay ordinary ids.
        #
        # The second arm needs no "at least one restart" of its own. At
        # zero restarts it would ask for `arrowhead_ends_id`, and the arm
        # in front already matches everything that could — so the first
        # arm wins there whatever the second one says. Requiring a restart
        # changed no verdict across 2761 probe cases, the whole 1997-case
        # corpus and the suite.
        rule(:arrowhead_dot_dash) do
          arrowhead_open | hunt(arrowhead_ends_id)
        end

        # Copied from the shape of mermaid's own dotted-link rule rather
        # than from the examples that happened to be probed. In
        # mmdc 11.12.0's flow lexer that rule is
        # `/^(?:\s*[xo<]?-?\.+-[xo>]?\s*)/`, so the opening carries a
        # marker on BOTH ends and may put a dash in front of the dots.
        #
        # Spelling only the middle of it read `x.-x` as `x.-` plus a
        # stray `x`, and every guard downstream restarted one character
        # early: `#x.-x --- Z` `#x.-xend --- Z` `1x.-x --- Z` `#o.-o --- Z`
        # and `x-.-1 --- Z` all parsed here while mmdc refuses them,
        # because mermaid had already taken the whole marker as one link
        # and the `---` behind it then had no node in front of it.
        #
        # `<` is in mermaid's leading set too and is left out on purpose:
        # it is not an id character here, so it can never be reached
        # inside one.
        rule(:arrowhead_open) do
          (str('x') | str('o')) >> str('-').maybe >> str('.').repeat(1) >>
            str('-') >> match['xo>'].maybe
        end

        # This checks for an arrowhead opening with nothing after it that
        # could continue an id.
        #
        # Sirena has no `x--` or `x-.-` link of its own yet, so it reads
        # `#x.-B` as one node where mermaid reads three. The two agree the
        # diagram is legal; they do not yet agree on what it holds.
        rule(:arrowhead_ends_id) { arrowhead_open >> id_body.absent? }

        # Mermaid's lexer spells its id charset out, so an id is not
        # "anything that is not punctuation". It is printable ASCII, or a
        # letter in the basic plane. A negated class took far more than
        # that: `😀 --- Z` parsed here and mmdc failed to lex it.
        #
        # Both halves were measured against mmdc a character at a time —
        # 168 sampled codepoints, then every ASCII control. Category and
        # plane both matter. `é` `中` `ª` and `Ａ` draw. `Ⅰ` does not,
        # because a Roman numeral is category Nl, not a letter. Nor does
        # `𝐀`, which is a letter but astral. Control characters,
        # combining marks, non-ASCII digits, braille and box drawing are
        # all refused too.
        #
        # `\p{L}` is close but not exact, so the letters come from
        # mermaid's own table instead (`MERMAID_UNICODE_TEXT`). How the
        # two differ, and why the table is copied rather than approximated,
        # is written down once beside the table in
        # `grammars/mermaid_unicode_text.rb`.
        #
        # `:` `,` `"` and `%` are printable ASCII and mermaid joins them —
        # it draws `A:B` `A,B` `A"B` and `A%B` as single nodes — but they
        # are held back on purpose, because each also opens something else
        # here: an inline class, a declaration list, a quoted label and a
        # comment. Letting them in needs those boundaries worked out
        # first, so it is left for its own change. A `;` is NOT one of
        # them: mermaid separates on it, and `A;B --- Z` draws `A` and
        # then `B --- Z`.
        # mmdc refuses `( ) < = > @ [ ] ^ { | } ~` outright.
        #
        # `-` and `.` are excluded here and handled by their own rules: a
        # hyphen only joins when a link cannot start there. Letting the
        # general class take them swallowed the `--` of `A-->B`.
        #
        # The class is written as three pieces because `restart_step`
        # has to tell them apart. An id itself takes any of the three.
        rule(:id_char) { id_ascii_char | id_carry_char | id_restart_char }

        rule(:id_ascii_char) do
          match['[\\u0021-\\u007E]&&[^;:,"%()<=>@\\[\\]^{|}~.\\-#&*0-9]']
        end

        # These carry mermaid's keyword hunt along rather than ending it.
        rule(:id_carry_char) { match['#&*0-9'] }

        # And a letter outside ASCII starts it over.
        rule(:id_restart_char) { match[MERMAID_UNICODE_TEXT] }

        # An id stops in front of an entity escape, and the guard belongs
        # to the RUN rather than to the character. `id_body` has a third
        # reader in `arrowhead_ends_id`, which asks a different question —
        # whether anything could continue an id behind a link opening — and
        # there a `#` still could. Guarding the character instead flips that
        # rule: measured, `arrowhead_ends_id` goes from no match to a match
        # on `x.-#a;` `x.-#a;B` and `o.-#35;`.
        #
        # No source changes verdict either way, because `arrowhead_dot_dash`
        # puts `arrowhead_open` in front and that arm already matches
        # everything the second could — the same reason written down beside
        # it. So this is blast radius, not a bug: one reader of `id_body` is
        # left exactly as it was.
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
        # it matches. Neither is anchored, so `stylex` and a `style:` inside
        # a label count: mmdc draws `stylex[foo:#bar]-->A#a;` and
        # `Z[style:#b]-->A#a;` because the `;` is gone before the escape
        # could form, and this refuses both. Modelling that needs a source
        # pre-pass, which this grammar has no place for yet, and origin/main
        # refuses the same sources for want of a `#` in an id at all.
        # Owner: the PR that models `encodeEntities` as a pre-pass — it also
        # owns the `style Z fill:#é;` over-acceptance left on main.
        #
        # The shape is exact and was measured either side of every part of
        # it: the run must be `[A-Za-z0-9_]`, and the `;` must abut it.
        # mmdc refuses `#a;B` `#35;B` `#x_;B` `Z#a;B` `##a;B` `#a#b;B`
        # `A-->B;#a;C` and `subgraph #ab_c;`, and draws `#;B` `1#;B`
        # `#a ;B` `#a\nB` `#é;B` and `#a.b;B` — none of which the rewrite
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
        # Taking a trailing comment here was therefore wrong for every input
        # it accepted. It drew `A` for `A%%c`, dropping text mermaid keeps,
        # and it drew `A` for `A %% c`, `A --> B %% c` and `A[T] %% c`,
        # which mmdc refuses outright. Widening node ids brought `1 %% c`
        # and its kin into the same arm, which is what made a rule that was
        # never right reachable from more of the corpus.
        #
        # The refusal is an under-acceptance for the abutting `A%%c` alone,
        # and closing that one means letting `%` into a node id — a widening
        # this PR does not make.
        #
        # The semicolon carried a `str('%%').absent?` of its own while the
        # comment arm was here. It is gone because nothing can reach it:
        # with no comment to take, `A;%% c` fails on the `%` either way.
        # Measured — the mutant survives all 1997 corpus cases and the
        # whole suite, while the same guard in `separator`, which is what
        # actually refuses `A;%% c`, kills 3 examples when it is removed.
        rule(:line_end) { semicolon.maybe >> space? >> (newline | eof) }
      end
    end
  end
end
