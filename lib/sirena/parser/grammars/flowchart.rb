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
        # node ids even though the characters are legal. Examples pin
        # `K-->Z` and `1K --> Z`; `K[L]` and `K.foo-->Z` were also measured
        # but are not asserted here. mmdc refuses all four for every word.
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
        # they share it here. `arrowhead_dot_dash` passes `min: 1` because
        # a BURIED opening has to cross at least one restart to be one;
        # every other caller takes the default and may match at the start.
        #
        # A `repeat` rather than a recursive rule: a rule that called
        # itself blew the Ruby stack on a 2000-character id, and mmdc
        # draws that id.
        def hunt(target, min = 0)
          (target.absent? >> restart_step).repeat(min) >> target
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
        # The text runs to the PHYSICAL end of the line, not to `line_end`
        # — that rule swallows a trailing comment, so `accTitle: %% c` came
        # back with no text at all where mmdc's title is `%% c`.
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
            # A subgraph body must begin on a new physical line.
            line_end >>
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
        # was refused here while mmdc draws it — and so is
        # `subgraph A B C [T]`. One rule for the whole tail keeps the two
        # from disagreeing about where the title may sit.
        #
        # `subgraph A [T] X` stays refused, which mmdc also refuses:
        # nothing may follow the title on the line.
        rule(:subgraph_trailing_name) do
          (space.repeat(1) >> subgraph_trailing_word).repeat >>
            (space.repeat(1) >> subgraph_title.as(:subgraph_title)).maybe
        end

        # `end` closes the subgraph, so it is a keyword in a trailing word
        # where it is an ordinary name in the first one: mmdc draws
        # `subgraph end [T]` and refuses `subgraph A end`. It is hunted the
        # way every other keyword is, so `subgraph A 1end` is refused too
        # while `subgraph A endx` draws.
        rule(:subgraph_trailing_word) do
          subgraph_end_id.absent? >> subgraph_name_word
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
        rule(:hashed_tail) do
          (structural_token.absent? >> declaration_char).repeat >>
            space? >> (comment.maybe >> newline | eof).present?
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
        # measured over 3680 cases, byte for byte — because an id holding
        # a keyword is refused by `node_id` before this guard is
        # reached; the value is that there is now one list to keep right.
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
        # A comment is not one of the endings either. Mermaid needs
        # whitespace right behind the word and `%%` is not whitespace, so
        # mmdc draws `href%%c` `call%%c` and `click%%c` as nodes.
        #
        # The end of the source IS one. Mermaid appends a newline before
        # it lexes, so a word at the very end is followed by one after
        # all. This rule is the only place that says so — a second copy
        # of it lived beside the id rules for a while, and it masked this
        # one so completely that deleting the `eof` here left every spec
        # green.
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
        rule(:node_with_shape) do
          node_id.as(:node_id) >>
            (ws? >> node_shape).maybe.as(:shape) >>
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

        # Bare `==` is not a link (mmdc rejects `A==B`). The arrow form is
        # two or more `=` followed by `>`. Mermaid's arrowhead-less thick
        # link `===` is REFUSED here rather than drawn, because this renderer
        # puts an arrowhead on every edge and drawing one where mermaid draws
        # none would be worse than refusing. Modelling open links is a
        # separate change.
        rule(:thick_arrow) do
          (str('=').repeat(2) >> str('>')).as(:thick)
        end

        # Dotted arrow: -.-> or -.-
        rule(:dotted_arrow) do
          (str('-.->') | (str('-.-') >> arrow_marker.absent?)).as(:dotted)
        end

        # Plain arrow: --> or --- or ->
        rule(:plain_arrow) do
          (str('-->') | (str('---') >> arrow_marker.absent?) |
            str('->')).as(:plain)
        end

        # A trailing `x` or `o` belongs to the LINK, not to the node behind
        # it. Mermaid's plain link is `[xo<]?--+[-xo>]` and its dotted one
        # is `[xo<]?-?\.+-[xo>]?`, so `A---x` is one link carrying a
        # crossed arrowhead, and `A---x --- Z` is refused for holding two
        # links with no node between them.
        #
        # Sirena draws no crossed or circled arrowhead, so the marker is
        # REFUSED rather than drawn with the wrong head — the same call
        # `thick_arrow` makes for the arrowhead-less `===` just above.
        # Modelling these heads is the change that also owns `1x-->B`.
        #
        # Widening node ids is what put these within reach: `#---x --- Z`
        # `1-.-o --- Z` `é---x --- Z` and 45 more parsed here while mmdc
        # refuses every one. Only the arrowhead-less forms need the guard;
        # after `-->` or `-.->` mermaid has already closed the link, so
        # the `x` in `A-->x` really is a node.
        rule(:arrow_marker) { match['xo'] }

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
        rule(:subgraph_id) { quoted_string | subgraph_name_word }

        rule(:subgraph_name_word) do
          subgraph_keyword_id.absent? >> dot_run_before_link.absent? >>
            subgraph_arrowhead.absent? >> id_run
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
          digit_id_before_link |
            (node_keyword_id.absent? >> dot_run_before_link.absent? >>
              arrowhead_dot_dash.absent? >> id_run)
        end

        # Measured against mmdc 11.12.0: a pure-digit node id ends before
        # one `x` or `o` when `--`, `==` or `-.` follows. A doubled `x`/`o`,
        # as in `1xx`, or any non-digit before the marker keeps it in the id.
        #
        # Sirena models no `x`/`o` link-start marker at all, so stopping
        # the id makes the statement fail. That is safer than drawing a
        # different graph with `1x` or `1o` as the node.
        rule(:digit_id_before_link) do
          match['0-9'].repeat(1) >>
            (match['xo'] >> (str('--') | str('==') | str('-.'))).present?
        end

        # A hyphen joins the id unless another dash or a dot follows, which
        # is where a link starts. Excluding `x`, `o` and `>` as well
        # rejected `a-o-->B` and `a-x-->B`, which mermaid renders; `A->B`
        # still fails because `>` alone is not a link.
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
        # opened a dotted link between the first two. Sirena has no
        # `-.-` link to build, so the id stops at the opening instead of
        # swallowing it and drawing a node that is not on mermaid's page.
        #
        # `arrowhead_dot_dash` below keeps the id in the same spot, and
        # the two are not in disagreement: there the opening is only a
        # link when nothing follows it, so an id can carry on past it.
        rule(:dot_run_before_link) { hunt(dotted_link_open) }

        # The same rule as `arrowhead_open` without its leading marker, so
        # it carries the same trailing one: mermaid's dotted link is
        # `[xo<]?-?\.+-[xo>]?` and the tail belongs to the link, not to the
        # id behind it.
        rule(:dotted_link_open) do
          str('.').repeat(1) >> str('-') >> match['xo>'].maybe
        end

        # Everywhere else a dot just joins, dash or no dash: mmdc draws
        # `A.-->B` as `A.` and `B`, and draws `A.-` `A.-B` `A..-->B` and
        # `y.- --> Z`.
        rule(:id_dot) { str('.') }

        # `arrowhead_dot_dash` recognizes `x.-` and `o.-` — an `x` or `o`,
        # then one or more dots, then a dash — as mermaid's dotted
        # left-arrowhead openings instead of ids. Where that opening is
        # legal decides the guard, and it was measured over 173 cases.
        #
        # At the id start nothing sits in front of the link, so mermaid
        # always refuses: `x.-` `x..-` `x.-z` and `x.-B` all fail. Behind
        # a lexer restart a node does sit in front, so the opening is a
        # real link and only fails when nothing follows it — `#x.- --> Z`
        # is refused while `#x.-B --- Z` draws.
        #
        # A settled character in front kills it either way, so `X.-`
        # `x1.-` `xx.-` and `xo.-` stay ordinary ids.
        rule(:arrowhead_dot_dash) do
          arrowhead_open | hunt(arrowhead_ends_id, 1)
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

        rule(:id_run) { id_body.repeat(1) }

        rule(:id_body) { id_dot | id_hyphen | id_char }

        # Line terminator
        # The optional semicolon here may not be followed by a comment on
        # the same line, matching the separator rule and mmdc: `A;%% c` is
        # rejected while `A;` then a `%% c` line is ordinary.
        #
        # Only the semicolon form is faithful. mmdc also rejects `A --> B %% c`
        # with no separator, and the `comment.maybe` arm below still takes it —
        # that arm predates this rule and tightening it is its own change.
        rule(:line_end) do
          (semicolon >> space? >> str('%%').absent?).maybe >>
            space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end
