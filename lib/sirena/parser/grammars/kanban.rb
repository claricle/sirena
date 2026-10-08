# frozen_string_literal: true

require_relative "common"
require_relative "../atoms/greedy_run"
require_relative "../atoms/joined"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Kanban diagrams
      class Kanban < Common
        rule(:diagram) do
          space_run >>
            header >>
            content_line.repeat(0).as(:lines) >>
            line_space_run
        end

        rule(:header) do
          str("kanban") >> (newline | eof)
        end

        # Nothing but blank and comment lines up to the end of the source.
        rule(:blank_lines_left) do
          (newline >> blank_text_run.maybe >> line_space_run >> eof) | eof
        end

        # The lines that capture nothing, taken as ONE slice. Parslet folds a
        # repetition of plain slices with `Slice#+`, which is quadratic, so
        # every repetition of such lines goes through `Joined`. A line that
        # captures (an item or a modifier) breaks the run and is never joined.
        rule(:blank_run) do
          Atoms::Joined.new(
            (empty_line | comment_line | no_op_modifier_line).repeat(1),
          )
        end

        # Only blank and comment lines: an empty `:::` is not one of them, and
        # `empty_class_modifier` looks ahead through this rule.
        rule(:blank_text_run) do
          Atoms::Joined.new((empty_line | comment_line).repeat(1))
        end

        rule(:content_line) do
          blank_run | modifier_line | item_line
        end

        rule(:empty_line) do
          line_space_run >> newline
        end

        # Overrides Common's char-at-a-time `comment` with the bounded
        # `GreedyRun` scan (see atoms/greedy_run.rb) so a long `%%` line
        # cannot hang this grammar; `.maybe` covers the empty-body `%%` case,
        # since GreedyRun itself errors on a zero-length match.
        #
        # The body stops at U+2028/U+2029, where mermaid's lexer `.*` stops.
        # Carriage returns never reach the grammar: the parser turns them
        # into line feeds first, as mermaid does.
        rule(:comment) do
          str("%%") >> Atoms::GreedyRun.new('[^\n\u2028\u2029]').maybe
        end

        # A line holding only a `%%` comment (corpus 032). Mermaid strips
        # such a line, up to its line feed, before lexing - so unlike a
        # trailing comment, its body runs through U+2028/U+2029 too. It
        # captures nothing, the same way empty_line doesn't -
        # Builders::Kanban's `rule(lines: subtree(:lines))` filters any
        # non-Hash entry out of the lines array.
        rule(:comment_line) do
          line_space_run >> str("%%") >> str("{").absent? >>
            Atoms::GreedyRun.new('[^\n]').maybe >> (newline | eof)
        end

        # How every item and modifier line ends: optional
        # whitespace, an optional trailing `%%` comment, then the line
        # break. After a closing delimiter (`]`, `)`, `}`) the comment needs
        # no space (`root[Root]%% c`); after a bare id `%%` is part of the
        # label, which `bare_item` refuses. Whitespace is mermaid's `\s`,
        # not Common's ASCII `space`.
        rule(:line_end) do
          (hspace_run >> comment >> comment_end) |
            (line_space_run >> (newline | eof))
        end

        # The comment body stops at U+2028/U+2029. Mermaid refuses one
        # unless only blanks and comments follow it to the end of the input.
        rule(:comment_end) do
          newline | eof |
            (line_sep >> line_space_run >>
              (blank_lines_left | (comment_line_start >> blank_lines_left)))
        end

        rule(:comment_line_start) do
          str("%%") >> str("{").absent? >>
            Atoms::GreedyRun.new('[^\n]').maybe
        end

        rule(:item_line) do
          Atoms::GreedyRun.new("[ ]", min: 0).as(:indent) >>
            item >>
            line_end
        end

        # An empty `::icon()` decorates nothing and may sit anywhere. An
        # empty `:::` swallows its own line break in mermaid's lexer, so the
        # next item would be joined onto it: it is accepted only when
        # nothing but blank or comment lines follow (measured against mmdc
        # 11.12.0).
        rule(:no_op_modifier_line) do
          space_run >>
            ((icon_keyword >> str(")") >> line_end) | empty_class_modifier)
        end

        rule(:empty_class_modifier) do
          str(":::") >> blank_lines_left.present?
        end

        # A standalone `::icon(...)` or `:::classes` line applies to the
        # PREVIOUS item rather than declaring one of its own - mermaid's
        # kanban shorthand for attaching an icon or classes without going
        # through `@{ ... }` metadata. Mirrors mindmap.rb's
        # `node_with_icon` / `node_with_class`, the existing precedent for
        # this exact shorthand in this grammar family; `Builders::Kanban`
        # applies it to the last item the same way mindmap's `TreeBuilder`
        # applies it to the last node.
        rule(:modifier_line) do
          space_run.as(:indent) >> (icon_modifier | class_modifier) >> line_end
        end

        rule(:icon_keyword) do
          str("::") >> match["iI"] >> match["cC"] >> match["oO"] >>
            match["nN"] >> str("(")
        end

        rule(:icon_modifier) do
          icon_keyword >>
            Atoms::GreedyRun.new("[^)]").as(:icon) >>
            str(")")
        end

        # The body stops where mermaid's `.+` does, at a line break or
        # U+2028/U+2029; `%%` inside it is class text.
        rule(:class_modifier) do
          str(":::") >>
            Atoms::GreedyRun.new('[^\n\u2028\u2029]').as(:classes)
        end

        # An item can be either a column or a card. The label is optional:
        # mermaid accepts a bare id, with or without trailing metadata.
        #
        # Named alternation branches rather than folding the bracket label
        # into one rule as a `.maybe`.
        # `bare_item` is the most permissive branch and must stay last, or a
        # later branch that also starts with an identifier would never be
        # reached. `shaped_item` and `labelled_item` both require a specific
        # delimiter (`(` or `[`) right after the id, so their relative order
        # does not matter - Parslet fails one and tries the next without
        # consuming input. `unlabelled_shaped_item` opens on `(`, something
        # an identifier can never start with, so it stays reachable
        # wherever it sits. Naming the branches keeps the order explicit
        # rather than implied, which is how the other grammars in this
        # directory are written - see `mindmap.rb`'s `node` rule.
        rule(:item) do
          reserved_token.absent? >>
            (labelled_item | shaped_item | unlabelled_shaped_item |
              bare_item) >>
            metadata.maybe.as(:metadata)
        end

        # `kanban` is the diagram's own header token, and mermaid reserves it
        # as a node name: it refuses `kanban`, `Kanban` and `KANBAN`, bare or
        # carrying a bracket label, as a column or as a card. Only the whole
        # word is taken - `kanbanBoard` and `mykanban` are legal ids. Measured
        # against mmdc 11.12.0.
        #
        # No other keyword is reserved. The tokens checked are listed once,
        # in the spec that pins them - see the 'reserves no other keyword'
        # example in spec/sirena/parser/kanban_spec.rb.
        rule(:reserved_token) do
          kanban_keyword >> match["a-zA-Z0-9_"].absent?
        end

        # Parslet's `str` is case-sensitive and it offers no case-insensitive
        # literal, so the keyword is spelled out character by character.
        rule(:kanban_keyword) do
          match["kK"] >> match["aA"] >> match["nN"] >>
            match["bB"] >> match["aA"] >> match["nN"]
        end

        # Common's `identifier` repeats a one-character match, which Parslet
        # folds with `Slice#+`: quadratic in the length of the id.
        rule(:identifier) do
          match["a-zA-Z_"] >> Atoms::GreedyRun.new("[a-zA-Z0-9_]", min: 0)
        end

        rule(:labelled_item) do
          identifier.as(:id) >>
            lbracket >>
            labelled_item_text >>
            rbracket
        end

        # Try the quoted form first: a quoted bracket label may contain `[`/`]`
        # literally, so the unquoted fallback below (which stops at the first
        # `]`) must not run against a quoted body. A markdown-string body
        # (`"`text`"`) is refused in both alternatives, as `round_text` does:
        # mermaid renders it as markdown and Sirena has no markdown renderer.
        rule(:labelled_item_text) do
          empty_quoted_fragments >>
            ((str('"') >> markdown_string_body.absent? >>
              Atoms::GreedyRun.new('[^"]').as(:text) >> str('"')) |
              ((str('"') >> markdown_string_body).absent? >>
                Atoms::GreedyRun.new('[^\]]').as(:text))) >>
            empty_quoted_fragments
        end

        # mermaid's lexer drops an empty quoted fragment (`""` or an empty
        # markdown string) beside the label text: `root[""a]` and
        # `root["a"""]` are both `a`, while `root[""]` with no text-bearing
        # fragment is refused.
        rule(:empty_quoted_fragment) do
          str('"``"') | str('""')
        end

        rule(:empty_quoted_fragments) do
          Atoms::Joined.new(empty_quoted_fragment.repeat)
        end

        # Round shape with an id: id(text) - mermaid's rounded-node syntax,
        # the same shorthand flowchart's `shape_rounded` parses. Sirena's
        # kanban renderer always draws a rounded rect for every item
        # regardless of source syntax (see Renderer::Kanban#render_column
        # and #render_card), so the delimiter is parsed only to recover the
        # label - no separate shape field is modeled, matching how the
        # bracket label above works.
        rule(:shaped_item) do
          identifier.as(:id) >>
            lparen >>
            round_text >>
            rparen
        end

        # Round shape with no id: (text). Mermaid auto-assigns an id here;
        # BoardBuilder does too, deterministically - see
        # Builders::Kanban::BoardBuilder#resolve_id.
        rule(:unlabelled_shaped_item) do
          lparen >>
            round_text >>
            rparen
        end

        # Text inside a round shape - id(text) or (text). A quoted body is
        # tried first so it can contain an unescaped `)`, mermaid's own
        # rule for `Todo (urgent)`, and the surrounding quotes are excluded
        # from the capture rather than kept as literal characters - mermaid
        # strips them too. Falls back to the plain, unquoted body when the
        # first character isn't a `"`. Mirrors `square_shape` in
        # mindmap.rb, the existing precedent for quoted content inside a
        # bracketed shape in this grammar family.
        #
        # The unquoted body excludes `(`, `)`, `]` and `}` - mermaid's own
        # lexer treats all four as node-shape delimiters even unquoted
        # mid-label, and rejects a body carrying one (measured against mmdc
        # 11.12.0). `[` and `{` are not delimiters to it there and stay
        # literal, so they are not excluded - both parse in mermaid.
        #
        # A quoted body that itself opens and closes with a backtick -
        # `"`text`"` - is mermaid's separate markdown-string syntax: it
        # strips the backtick pair and renders the content through
        # markdown, formatting included (`col("`Hi **urgent**`")` draws
        # `Hi <strong>urgent</strong>` in mmdc 11.12.0). Sirena has no
        # markdown renderer anywhere in the codebase, so matching this as
        # an ordinary quoted body would keep the backticks as literal text
        # and silently draw something mermaid does not. Refused instead,
        # the same way an empty or unterminated quoted body is refused
        # below, rather than half-supporting a shape nothing here
        # understands.
        rule(:round_text) do
          empty_quoted_fragments >>
            ((str('"') >> markdown_string_body.absent? >>
              Atoms::GreedyRun.new('[^"]').as(:text) >> str('"')) |
              (str('"').absent? >>
                Atoms::GreedyRun.new('[^()\]}]').as(:text))) >>
            empty_quoted_fragments
        end

        rule(:markdown_string_body) do
          str("`") >> Atoms::GreedyRun.new('[^"`]', min: 0) >>
            str("`") >> str('"')
        end

        # Deliberately just an identifier. Mermaid also accepts a bare label
        # containing spaces, but widening this to free text would swallow
        # `root(Root)` and `:::hot` as literal labels, turning unsupported
        # constructs into silently wrong output instead of parse failures.
        # `identifier` also refuses a leading digit, so `1col` fails to parse
        # while `col1` and `_col` are accepted.
        # Trailing `%%`, or trailing JavaScript whitespace beyond space and
        # tab, is part of a bare id's literal label in mermaid, so it is
        # refused here rather than dropped by `line_end`.
        rule(:bare_item) do
          identifier.as(:id) >>
            (space_run >> (str("%%") | line_space)).absent?
        end

        LINE_SPACE_CHARS = '\t\v\f\x20\u00A0\u1680' \
                           '\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF'
        HSPACE_CHARS = '\t\v\f\x20\u00A0\u1680' \
                       '\u2000-\u200A\u202F\u205F\u3000\uFEFF'
        private_constant :LINE_SPACE_CHARS, :HSPACE_CHARS

        rule(:line_space) { match[LINE_SPACE_CHARS] }
        rule(:line_sep) { match['\u2028\u2029'] }

        # Whitespace runs go through `GreedyRun`: Parslet's own
        # `line_space.repeat` is quadratic in the length of the run.
        rule(:line_space_run) do
          Atoms::GreedyRun.new("[#{LINE_SPACE_CHARS}]", min: 0)
        end

        rule(:space_run) { Atoms::GreedyRun.new("[ \\t]", min: 0) }

        rule(:hspace_run) do
          Atoms::GreedyRun.new("[#{HSPACE_CHARS}]", min: 0)
        end

        # Metadata: @{ key: 'value', key2: 'value2' } - or newline-separated
        # with no commas (corpus 038). The body is captured RAW, as
        # `flowchart.rb`'s `node_metadata` does, and handed to a YAML engine
        # in the builder (`MetadataYaml`): a grammar rule cannot express
        # "block vs flow, decided by whether a newline appears ANYWHERE in
        # the body" without reimplementing a YAML lexer.
        #
        # `metadata_entries` is the grammar seam: its default is that raw
        # capture, and a subclass that overrides it controls the tree
        # `metadata` holds. The builder reads only `:body` from it, so an
        # override that drops `:body` gives the item no metadata.
        rule(:metadata) do
          str("@") >> space_run >> lbrace >> metadata_entries >> rbrace
        end

        # An unmatched `"` is not body text - mermaid's lexer stays in its
        # string state to the end of the block and refuses the source.
        # A caret is not body text either: mermaid takes the run between
        # the braces with `[^}^"]+`, so a `^` outside a quoted value ends
        # the block early.
        rule(:metadata_body) do
          Atoms::Joined.new(
            (Atoms::GreedyRun.new('[^"}^\n]') | blank_line_run |
              metadata_comment_line | metadata_quoted | newline).repeat,
          )
        end

        # Every line break that another one follows; the last stays for
        # `metadata_comment_line`, which opens on a line break.
        rule(:blank_line_run) do
          Atoms::GreedyRun.new('\r?\n(?=\r?\n)')
        end

        # Mermaid strips comment lines before the metadata lexer sees them.
        rule(:metadata_comment_line) do
          newline >> line_space_run >> str("%%") >> str("{").absent? >>
            Atoms::GreedyRun.new('[^\r\n]')
        end

        # A double-quoted run is skipped whole so a brace inside it is text,
        # mirroring flowchart.rb's `metadata_quoted`. A comment line inside
        # it is still a comment: mermaid strips those before lexing.
        rule(:metadata_quoted) do
          str('"') >>
            (metadata_comment_line | Atoms::GreedyRun.new('[^"\n]') |
              newline).repeat >>
            str('"')
        end

        # The next 5 rules are public methods released in sirena 0.1.0: do
        # not delete or rename them outside a major version. Only
        # `metadata_entries` is on the parse path; the other four are
        # building blocks a subclass may use inside its own override.
        rule(:metadata_entries) do
          metadata_body.as(:body)
        end

        rule(:metadata_entry) do
          metadata_key.as(:key) >>
            space_run >>
            colon >>
            space_run >>
            metadata_value.as(:value)
        end

        rule(:metadata_key) do
          match["a-zA-Z_"] >> Atoms::GreedyRun.new("[a-zA-Z0-9_]", min: 0)
        end

        rule(:metadata_value) do
          quoted_string | single_quoted_string | unquoted_value
        end

        # Captured as :unquoted, not :string, so an override of
        # `metadata_entries` can tell an unquoted scalar from a quoted one.
        #
        # `.`, `+` and `~` are in the set because js-yaml reads them and
        # mermaid draws them: `0.0`, `+0`, `~` and `.nan` are values it
        # resolves falsy, and `1.5` and `+7` values it keeps. Without them
        # the whole line failed to parse. None of the three ends a value -
        # a comma or a closing brace does - so the rule stays unambiguous.
        rule(:unquoted_value) do
          Atoms::GreedyRun.new('[a-zA-Z0-9_\-.+~]').as(:unquoted)
        end

        root(:diagram)
      end
    end
  end
end
