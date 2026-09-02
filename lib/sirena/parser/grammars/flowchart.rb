# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Flowchart diagrams.
      #
      # Handles flowchart syntax including nodes with various shapes,
      # edges with labels, edge chaining, subgraphs, and styling directives.
      class Flowchart < Common
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

        # Subgraph: subgraph id [title] ... end, or `subgraph id title`
        # with the rest of the line as the title.
        rule(:subgraph_statement) do
          str('subgraph').as(:subgraph_keyword) >> space >>
            subgraph_id.as(:subgraph_id) >>
            subgraph_title.maybe >>
            declaration_end >>
            ws? >>
            statements.maybe.as(:subgraph_statements) >>
            ws? >>
            str('end').as(:subgraph_end) >>
            subgraph_close
        end

        # `end` names a subgraph only with a title behind it. Mermaid
        # resolves the bare form inconsistently — it draws `subgraph end`
        # with a plain body, and refuses the same declaration with an empty
        # body or a nested subgraph. Refusing all three is the only reading
        # that never claims something mmdc will not draw.
        # A quoted id is named here rather than in `node_id`, because the
        # two positions do not agree. mmdc 11.12.0 draws
        # `subgraph "a b"` and REFUSES `"a" --> b`, so a node id stays a
        # bare identifier while a box may carry quotes.
        rule(:subgraph_id) do
          (subgraph_terminator >> subgraph_title.present?) |
            (subgraph_terminator.absent? >> empty_quotes.absent? >>
              (quoted_string | node_id))
        end

        # mmdc refuses `subgraph ""` and `subgraph "" [T]`, and an empty
        # capture is not an empty string here — it arrives as an empty
        # array, so the box came out named `[]` and titled `[]`.
        rule(:empty_quotes) { str('""') }

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
            (title_word >> (space.repeat(1) >> title_word).repeat)
              .as(:subgraph_free_title)
        end

        rule(:title_word) { title_char.repeat(1) }

        rule(:title_char) { match['^ \t;\n\r()<>{}\[\],=@|~'] }

        # A semicolon run separates statements here as it does after `end`,
        # and a comment is not a statement: mmdc renders `subgraph s;;A`
        # and refuses `subgraph s; %% note`.
        rule(:declaration_end) do
          space? >> (semicolon_run >> no_comment | newline | eof)
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

        # Whole word only: a node called `endpoint` is not a terminator.
        # The boundary is "no identifier character follows", not "a space
        # follows" — `end[Label]` was a node under the looser test, and
        # mermaid rejects that source.
        rule(:subgraph_terminator) do
          str('end') >> match['a-zA-Z0-9_'].absent?
        end

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
        rule(:click_statement) do
          str('click').as(:click_keyword) >> space >>
            node_id.as(:click_target) >>
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
        rule(:reserved_keyword) do
          spaced_keyword | separable_keyword
        end

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
        rule(:spaced_keyword) do
          (str('click') | str('href') | str('call')) >>
            (space | newline | eof).present?
        end

        # The boundary is a word boundary, not a space or a separator:
        # mmdc refuses `style[x]` and `_blank-->Z`, which the narrower test
        # let through.
        #
        # Longest first — Parslet does not backtrack into an alternative
        # that already matched, so `class` ahead of `classDef` would take
        # five characters and then fail the boundary.
        rule(:separable_keyword) do
          ((str('interpolate') | str('flowchart') | str('linkStyle') |
            str('subgraph') | str('classDef') | str('style') |
            str('graph') | str('class') | str('end')) >>
            word_boundary) | link_target
        end

        # mermaid's link targets. They close a click action and they are
        # never node ids, so both places name them here.
        rule(:link_target) do
          (str('_parent') | str('_blank') | str('_self') | str('_top')) >>
            word_boundary
        end

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

        # Thick arrow: ==> or ==
        rule(:thick_arrow) do
          (str('==>') | str('==')).as(:thick)
        end

        # Dotted arrow: -.-> or -.-
        rule(:dotted_arrow) do
          (str('-.->') | str('-.-')).as(:dotted)
        end

        # Plain arrow: --> or --- or ->
        rule(:plain_arrow) do
          (str('-->') | str('---') | str('->')).as(:plain)
        end

        # Edge label: can be in pipes |label|
        rule(:edge_label) do
          pipe_label
        end

        # Pipe label: |label|
        rule(:pipe_label) do
          pipe >> (pipe.absent? >> any).repeat(1) >> pipe
        end

        # A node id is a bare word. A quoted run was never one: mmdc
        # refuses `"A" --> B`, `A --> "B"`, `"A"[x]`, `style "A" fill:red`
        # and a quoted run standing alone on a line. All it ever produced
        # here was a node whose id was a stringified parse tree —
        # `{string: "tip"@12}` — so the alternative drew garbage where
        # mermaid draws nothing.
        rule(:node_id) { identifier }

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
