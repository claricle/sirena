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

        rule(:header) do
          (str('flowchart') | str('graph')).as(:header) >>
            ws? >>
            direction.maybe.as(:direction) >>
            separator.maybe
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

        rule(:direction) do
          (str('TD') | str('TB') | str('LR') | str('RL') | str('BT')).as(:dir_value)
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
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
            statement_end
        end

        rule(:subgraph_title) do
          lbracket >> (rbracket.absent? >> any).repeat(1) >> rbracket
        end

        # Style: style nodeId fill:#f9f
        rule(:style_statement) do
          str('style').as(:style_keyword) >> space >>
            node_id.as(:style_target) >>
            (space >> style_property_list).as(:style_props) >>
            statement_end
        end

        # A `;` continues a declaration list only when another `key:value`
        # follows it. Otherwise it terminates the statement, so
        # `style A fill:#f9f;B` keeps `B` as a node instead of swallowing it
        # into the value — mermaid renders B, and scanning to the end of the
        # line dropped it silently.
        rule(:style_property_list) do
          style_property >>
            (semicolon >> space? >> continues_list.present? >> style_property)
              .repeat
        end

        # Permissive, exactly as before: mermaid takes `style A red`,
        # `style A fill:` and `style A fill :red`, and requiring `name:value`
        # here rejected all three.
        rule(:style_property) do
          (line_end.absent? >> semicolon.absent? >> comma.absent? >> any)
            .repeat(1)
        end

        # Only the decision after a `;` is strict. Text shaped like `name:`
        # continues the declaration list; anything else means the `;`
        # terminated the statement, so `style A fill:#f9f;B` leaves B to be
        # parsed as a node instead of swallowing it.
        rule(:continues_list) do
          (match['\s:;,'].absent? >> any).repeat(1) >> space? >> str(':')
        end

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
            node_id.as(:class_target) >> space >>
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

        # An action is required — mmdc rejects a bare `click A`. The scan is
        # quote-aware so a `;` inside a URL or tooltip stays part of the
        # action while an unquoted one ends the statement, which is what
        # mermaid does with `click A "http://x";B`.
        rule(:click_action) do
          (quoted_run | (unspaced_separator.absent? >> line_end.absent? >>
                         semicolon.absent? >> any)).repeat(1)
        end

        # The action must not run up to a spaced separator and leave it for
        # the terminator, which turned `click A "u" ;B` into a click plus a
        # node B. mmdc rejects that source outright.
        rule(:unspaced_separator) { space >> semicolon }

        rule(:quoted_run) do
          str('"') >> (str('"').absent? >> any).repeat >> str('"')
        end

        # A statement keyword is not a node id. Without this a malformed
        # directive fell through to the node rules: `click ;B` produced
        # nodes `click` and `B`, and mmdc rejects the whole source.
        rule(:reserved_keyword) do
          (str('classDef') | str('linkStyle') | str('subgraph') |
            str('click') | str('style') | str('class')) >>
            (space | semicolon | line_end).present?
        end

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

        # Node with optional shape definition
        rule(:node_with_shape) do
          node_id.as(:node_id) >>
            (ws? >> inline_class.as(:inline_class)).maybe >>
            (ws? >> node_shape.as(:shape)).maybe
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
            node_with_shape.as(:target)
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

        # Node identifier
        rule(:node_id) do
          quoted_string | identifier
        end

        # Line terminator
        rule(:line_end) do
          semicolon.maybe >> space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end