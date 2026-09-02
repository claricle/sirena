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
            node_id.as(:subgraph_id) >>
            (space >> subgraph_title.as(:subgraph_title)).maybe >>
            ws? >>
            statements.maybe.as(:subgraph_statements) >>
            ws? >>
            str('end').as(:subgraph_end) >>
            loose_statement_end
        end

        rule(:subgraph_title) do
          lbracket >> (rbracket.absent? >> any).repeat(1) >> rbracket
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

        # One `x` or `o` and then a link body, with nothing between them.
        rule(:flush_link_marker) { match['xo'] >> link_body }

        # Node with optional shape and edges
        #
        # A lone `x` or `o` sitting flush against a link body is mermaid's
        # link-START marker, not a node called `x`. mmdc reads `x===B` as
        # a link with nothing on its left and refuses it, while it draws
        # `xx===B` and `x === B` — the marker has to be one character and
        # flush. `flush_link_marker` refuses exactly that shape.
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
        # On its second branch the `:shape` slot comes back nil:
        # `dot_absent` is a zero-width lookahead and captures nothing. It
        # is there only to refuse the flush dot a bare name would
        # otherwise swallow.
        rule(:node_with_shape) do
          flush_link_marker.absent? >>
            node_id.as(:node_id) >>
            ((ws? >> node_shape).as(:shape) | dot_absent.as(:shape)) >>
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
        # Sirena's own names take no dot, so it refuses all six of those
        # — `A.-B`, `A:::c.-B`, `A[x]:::c.-B` and the three `.->` forms —
        # rather than naming a node or a class after one. Refusing is what
        # it did before; reading a link there would not be.
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

        # `~~~` takes no markers at all: mmdc rejects `o~~~o` and `~~~>`.
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
