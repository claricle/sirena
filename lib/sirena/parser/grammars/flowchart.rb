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

        # Subgraph: subgraph id [title] ... end
        rule(:subgraph_statement) do
          str('subgraph').as(:subgraph_keyword) >> space >>
            subgraph_id.as(:subgraph_id) >>
            subgraph_trailing_name >>
            # A subgraph body must begin on a new physical line. The gap
            # in front of the `;` is the one node statements already
            # tolerate in `loose_separator`: mmdc draws `A ;` and `end ;`
            # as readily as `A;`. `line_space`, not `space?`, because
            # mermaid's lexer eats its whole space set here, so
            # `subgraph A` no-break-space `;` draws.
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
            (space.repeat(1) >> subgraph_title.as(:subgraph_title)).maybe
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
        # the tree has one shape instead of one per combination.
        #
        # The shape opening abuts the id, with no gap of any kind: mmdc
        # refuses `A [B]`, `A\t[B]`, `A\n[B]` and `A %% c\n[B]` alike.
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

        # Bare `==` is not a link (mmdc rejects `A==B`). A thick link has
        # at least two `=` before an arrowhead or at least three without
        # one. The headed arm comes first so its `>` is not left for the
        # target.
        #
        # The open arm carries `trailing_xo_marker.absent?` for the same
        # reason the other two links do. Mermaid's thick link is
        # `[xo<]?==+[=xo>]`, so the trailing `x` belongs to the LINK: mmdc
        # draws `A===xB` as `A` and `B` joined by one crossed-head link,
        # and refuses `A===x`, `A===o` and `A===x --- Z`.
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

        # Mermaid's plain link is `--+[-xo>]`: two or more dashes, then ONE
        # of `-`, `x`, `o`, `>`. The dashes are counted rather than
        # spelled, so `A----B`, `A--->B` and `A-----B` all draw one edge.
        #
        # A bare `->` is NOT a plain link: mmdc refuses `A->B`, `A -> B`,
        # `A ->B` and `A-> B` alike.
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
        # REFUSED rather than drawn with the wrong head. Modelling these
        # heads is the change that also owns `1x-->B`.
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
          quoted_run | (str('""') >> space.repeat >> subgraph_name_word) |
            subgraph_name_word
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
        # Sirena models no `x`/`o` link-start marker, so stopping the id
        # makes the statement fail. That is safer than drawing a different
        # graph with `1x` or `#x` as the node.
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
        # statement — not because `->` is unknown; `A -> B` is
        # `plain_arrow`'s refusal instead.
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
        # dotted link between the first two. Sirena has no link for that
        # opening (`dotted_arrow` builds `-.-` and `-.->`, not a run that
        # starts on the dot), so the id stops at it instead of drawing a
        # node that is not on mermaid's page.
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
        # id. Sirena has no `x--` or `x-.-` link of its own yet, so
        # `id_before_xo_link` stops the id at the restart and the source is
        # refused until the crossed head has a shape to draw.
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
