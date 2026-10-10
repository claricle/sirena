# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Mindmap diagrams
      class Mindmap < Common
        rule(:diagram) do
          space? >>
            header >>
            node_line.repeat(0).as(:nodes) >>
            space?
        end

        # Mermaid does not require whitespace between the "mindmap" keyword
        # and the root node: any content left on the header's own line
        # becomes the root, handled below by node_line falling through to
        # node_with_content with a zero-length indent.
        rule(:header) do
          str("mindmap") >> match["a-zA-Z0-9_"].absent? >> header_tail
        end

        # A run of separators after the keyword is only ever discarded when
        # nothing but a comment or the line end follows it: mermaid's own
        # lexer never treats that whitespace as a token, so there is no
        # indent to preserve. When something else follows on the same line
        # (an inline root), that whitespace IS the root's SPACELIST token in
        # mermaid's grammar and sets mindmapDb's baseLevel for every later
        # line's indent to be measured against -- so here we consume nothing
        # and leave it for node_line's own indent capture.
        rule(:header_tail) do
          (match[' \t'].repeat >> comment >> (newline | eof)) |
            (match[' \t'].repeat >> (newline | eof)) |
            str("")
        end

        rule(:node_line) do
          empty_line | node_with_content
        end

        rule(:empty_line) do
          space? >> newline
        end

        # A shaped node's own rule stops at its shape's closing delimiter, so
        # a same-line trailing "%%" comment -- valid anywhere in mermaid's
        # lexer -- is tolerated here, once, for every SHAPED node type,
        # rather than inside each shape rule. node_plain has no closing
        # delimiter: its content rule (`match('[^\r\n:]').repeat(1)`, below)
        # already greedily swallows a trailing "%%..." into :content before
        # this `comment.maybe` ever runs, so a plain node's trailing comment
        # is NOT stripped. Pre-existing, not introduced by this change;
        # left as-is here, out of scope for this fix.
        rule(:node_with_content) do
          match[' \t'].repeat.as(:indent) >>
            node >>
            space? >>
            comment.maybe >>
            (newline | eof)
        end

        rule(:node) do
          node_with_icon |
            node_with_class |
            node_with_shape |
            node_plain
        end

        # Node with icon: ::icon(fa fa-book)
        rule(:node_with_icon) do
          str("::icon(") >>
            match("[^)]").repeat(1).as(:icon) >>
            str(")")
        end

        # Node with class: :::className
        rule(:node_with_class) do
          str(":::") >>
            match('[^\r\n]').repeat(1).as(:classes)
        end

        # Node with shape (optional identifier prefix). round_shape must be
        # tried last: circle_shape's "((" is a strict prefix of a lone "(",
        # so round_shape would otherwise swallow the first paren of a circle
        # node and leave its own close paren unconsumed.
        rule(:node_with_shape) do
          match["a-zA-Z0-9_"].repeat >>
            (circle_shape | bang_shape | cloud_shape | hexagon_shape | square_shape | round_shape)
        end

        # ((text)) - circle
        rule(:circle_shape) do
          str("((") >>
            match("[^)]").repeat(1).as(:content) >>
            str("))") >>
            str("").as(:shape_circle)
        end

        # ))text(( - bang
        rule(:bang_shape) do
          str("))") >>
            match("[^(]").repeat(1).as(:content) >>
            str("((") >>
            str("").as(:shape_bang)
        end

        # )text( - cloud
        rule(:cloud_shape) do
          str(")") >>
            match("[^(]").repeat(1).as(:content) >>
            str("(") >>
            str("").as(:shape_cloud)
        end

        # {{text}} - hexagon
        rule(:hexagon_shape) do
          str("{{") >>
            match("[^}]").repeat(1).as(:content) >>
            str("}}") >>
            str("").as(:shape_hexagon)
        end

        # [text] - square (handles quoted content like ["text with []"])
        rule(:square_shape) do
          str("[") >>
            (
              # Quoted content: ["text..."]
              (str('"') >> match('[^"]').repeat(1).as(:content) >> str('"')) |
              # Regular content without quotes
              match('[^\]]').repeat(1).as(:content)
            ) >>
            str("]") >>
            str("").as(:shape_square)
        end

        # (text) - round (rounded rectangle, mermaid's default shape spelled
        # out explicitly). Content may span multiple physical lines: unlike
        # node_with_content's own line-at-a-time repeat, nothing inside this
        # rule stops at a newline, only the closing ")" does -- matching
        # mermaid's own NODE-state lexer, whose catch-all token for this
        # shape does not stop at line breaks either. Quoted content (e.g.
        # `root("a)b")`) mirrors square_shape's own quoted branch: mermaid's
        # lexer has a dedicated quoted-content state that strips the quotes
        # and lets a literal ")" through, which the unquoted `[^)]` branch
        # cannot represent.
        # Mermaid's own comment-strip regex runs `\s` from JavaScript, which
        # is far wider than ASCII space/tab -- it also matches a no-break
        # space and the other Unicode space separators below. Mirrors
        # Builders::Flowchart::JS_SPACE (flowchart.rb), the same character
        # set for the identical "indentation before %%" problem.
        COMMENT_INDENT = '\t\n\v\f\r \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff'

        rule(:round_comment_line) do
          newline >>
            match[COMMENT_INDENT].repeat >>
            str("%%") >>
            str("{").absent? >>
            match('[^\r\n]').repeat >>
            newline.maybe
        end

        rule(:round_unquoted_content) do
          (round_comment_line | match("[^)]")).repeat(1).as(:content)
        end

        # A %% comment line embedded inside quoted round content is matched
        # the SAME way as the unquoted case above, before the closing quote
        # is ever searched for. Mermaid strips comment lines in a textual
        # pre-pass that runs before quote lexing, so a literal `"` sitting
        # inside what will become a stripped comment line does not end the
        # quoted string in real mermaid -- matching only `[^"]` per
        # character let such a `"` end the match early, breaking the whole
        # round_shape alternative and falling back to plain-text nodes.
        rule(:round_quoted_content) do
          (round_comment_line | match('[^"]')).repeat(1).as(:content)
        end

        rule(:round_shape) do
          str("(") >>
            (
              (str('"') >> round_quoted_content >> str('"') >>
                str("").as(:round_quoted)) |
              round_unquoted_content
            ) >>
            str(")") >>
            str("").as(:shape_round)
        end

        # Plain text node
        rule(:node_plain) do
          match('[^\r\n:]').repeat(1).as(:content)
        end

        root(:diagram)
      end
    end
  end
end
