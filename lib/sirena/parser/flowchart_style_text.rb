# frozen_string_literal: true

require 'strscan'
require_relative '../error/parse_error'

module Sirena
  module Parser
    # Refuses style/classDef/linkStyle value text mermaid's own lexer cannot
    # take. mermaid tokenizes the whole document with one jison scanner
    # (chunk-MX3EQCGM.mjs, `conditions.INITIAL.rules`, first-match-wins, no
    # longest-match), and its grammar accepts only 13 token kinds in a
    # `styleComponent` value; anything else is a real parse error mermaid
    # would raise. `RULES` below is that scanner's INITIAL rule table,
    # ported verbatim and in order from the same bundle, measured against
    # the mermaid-cli 11.12.0 oracle.
    class FlowchartStyleText
      # The character-class body shared by `JS_SPACE` below and by
      # `LINK_LIMIT` further down, which needs the same set unioned with a
      # few extra characters rather than nested inside it — Ruby has no
      # way to reuse a bracket expression's contents except by keeping the
      # unwrapped body as its own constant.
      JS_SPACE_CHARS = '\t\n\v\f\r \u00a0\u1680\u2000-\u200a' \
                        '\u2028\u2029\u202f\u205f\u3000\ufeff'

      # JavaScript's `\s`, used by `\bhref\b`/`\bcall\b`/`\bclick\b`,
      # `encodeEntities`'s own scan below, and by every `\s` in `RULES` —
      # Ruby's `\s` is only the five ASCII whitespace characters, so every
      # rule that reads `\s` in the live bundle is built from this constant
      # instead. The set is JavaScript's exactly: the line/paragraph
      # separators and the byte-order mark are in it; the next-line
      # character and the zero-width space are not. The builder also reads
      # this constant (it needs the same set for the quoted-newline rule),
      # so it is not `private_constant`.
      JS_SPACE = "[#{JS_SPACE_CHARS}]".freeze

      # JavaScript's `.` without the `s` flag excludes four characters —
      # \n, \r, and the two Unicode line/paragraph separators already
      # inside `JS_SPACE_CHARS` — where Ruby's bare `.` excludes only \n.
      # Used by `STYLE_RUN`/`CLASS_DEF_RUN` below wherever the live
      # bundle's own regex reads a bare `.`; the lookahead-guarded `.`
      # between them already excludes all four through `JS_SPACE`, so it
      # needs no substitution.
      JS_DOT = '[^\n\r\u2028\u2029]'

      # JavaScript's `\b` without the `u` flag is ASCII-only: `\w` is
      # `[A-Za-z0-9_]`, so `é` is not a word character and `endé` is past
      # the boundary the moment `end` finishes matching. Ruby's `\b` is
      # Unicode-aware and treats `é` as a word character, so every rule
      # below that reads `\b` in the live bundle ends with this lookahead
      # instead — all of them anchor a keyword's end, never its start, so
      # a trailing assertion is enough.
      ASCII_WORD_END = '(?![A-Za-z0-9_])'

      # mermaid glues the last `;` of a lowercase `style ...:#...;` run, then
      # of a `classDef ...:#...;` run, onto the entity before ever
      # tokenizing (`encodeEntities`). Both bare `.*` spans here must stay
      # `JS_DOT`, not Ruby's own `.` — a JS line terminator (\r, U+2028,
      # U+2029) ends the run in the live bundle, and must end it here too,
      # or a `;` mermaid keeps gets stripped and an entity mermaid refuses
      # gets silently accepted.
      STYLE_RUN = /style#{JS_DOT}*:(?:(?!#{JS_SPACE}).)*##{JS_DOT}*;/
      CLASS_DEF_RUN = /classDef#{JS_DOT}*:(?:(?!#{JS_SPACE}).)*##{JS_DOT}*;/
      ENTITY = /#\w+;/

      # The INITIAL-condition lexer rules, in the bundle's own declaration
      # order — jison tries them in this order at every position and stops
      # at the first regex that matches, so the order is load-bearing.
      # Each pattern is anchored with `\G`, not `\A`, so `scan` below can
      # match at any offset into the full statement text without slicing a
      # fresh substring per token. `nil` marks a rule whose `performAction`
      # case does a state transition with no `return`: it consumes input
      # but hands back no token, which in a style value position is always
      # a refusal. `:STRING_OPEN` marks the one rule `scan` must treat
      # differently — it opens the "string" lexer condition simulated by
      # `scan_string_body` below.
      RULES = [
        ["acc_title", Regexp.new("\\G(?:accTitle#{JS_SPACE}*:#{JS_SPACE}*)")].freeze,
        ["acc_descr", Regexp.new("\\G(?:accDescr#{JS_SPACE}*:#{JS_SPACE}*)")].freeze,
        [nil, Regexp.new("\\G(?:accDescr#{JS_SPACE}*\\{#{JS_SPACE}*)")].freeze,
        ["SHAPE_DATA", Regexp.new('\\G(?:@\\{)')].freeze,
        [nil, Regexp.new("\\G(?:call#{JS_SPACE}+)")].freeze,
        [nil, Regexp.new('\\G(?:["][`])')].freeze,
        [:STRING_OPEN, Regexp.new('\\G(?:["])')].freeze,
        ["STYLE", Regexp.new("\\G(?:style#{ASCII_WORD_END})")].freeze,
        ["DEFAULT", Regexp.new("\\G(?:default#{ASCII_WORD_END})")].freeze,
        ["LINKSTYLE", Regexp.new("\\G(?:linkStyle#{ASCII_WORD_END})")].freeze,
        ["INTERPOLATE", Regexp.new("\\G(?:interpolate#{ASCII_WORD_END})")].freeze,
        ["CLASSDEF", Regexp.new("\\G(?:classDef#{ASCII_WORD_END})")].freeze,
        ["CLASS", Regexp.new("\\G(?:class#{ASCII_WORD_END})")].freeze,
        ["HREF", Regexp.new("\\G(?:href#{JS_SPACE})")].freeze,
        [nil, Regexp.new("\\G(?:click#{JS_SPACE}+)")].freeze,
        ["GRAPH", Regexp.new("\\G(?:flowchart-elk#{ASCII_WORD_END})")].freeze,
        ["GRAPH", Regexp.new("\\G(?:swimlane-beta#{ASCII_WORD_END})")].freeze,
        ["GRAPH", Regexp.new("\\G(?:graph#{ASCII_WORD_END})")].freeze,
        ["GRAPH", Regexp.new("\\G(?:flowchart#{ASCII_WORD_END})")].freeze,
        ["subgraph", Regexp.new("\\G(?:subgraph#{ASCII_WORD_END})")].freeze,
        ["end", Regexp.new("\\G(?:end#{ASCII_WORD_END}#{JS_SPACE}*)")].freeze,
        ["LINK_TARGET", Regexp.new("\\G(?:_self#{ASCII_WORD_END})")].freeze,
        ["LINK_TARGET", Regexp.new("\\G(?:_blank#{ASCII_WORD_END})")].freeze,
        ["LINK_TARGET", Regexp.new("\\G(?:_parent#{ASCII_WORD_END})")].freeze,
        ["LINK_TARGET", Regexp.new("\\G(?:_top#{ASCII_WORD_END})")].freeze,
        ["direction_tb", Regexp.new("\\G(?:#{JS_DOT}*direction#{JS_SPACE}+TB[^\\n]*)")].freeze,
        ["direction_bt", Regexp.new("\\G(?:#{JS_DOT}*direction#{JS_SPACE}+BT[^\\n]*)")].freeze,
        ["direction_rl", Regexp.new("\\G(?:#{JS_DOT}*direction#{JS_SPACE}+RL[^\\n]*)")].freeze,
        ["direction_lr", Regexp.new("\\G(?:#{JS_DOT}*direction#{JS_SPACE}+LR[^\\n]*)")].freeze,
        ["direction_td", Regexp.new("\\G(?:#{JS_DOT}*direction#{JS_SPACE}+TD[^\\n]*)")].freeze,
        ["LINK_ID", Regexp.new("\\G(?:[^#{JS_SPACE}\\\"]+@(?=[^\\{\\\"]))")].freeze,
        ["NUM", Regexp.new('\\G(?:[0-9]+)')].freeze,
        ["BRKT", Regexp.new('\\G(?:#)')].freeze,
        ["STYLE_SEPARATOR", Regexp.new('\\G(?::::)')].freeze,
        ["COLON", Regexp.new('\\G(?::)')].freeze,
        ["AMP", Regexp.new('\\G(?:&)')].freeze,
        ["SEMI", Regexp.new('\\G(?:;)')].freeze,
        ["COMMA", Regexp.new('\\G(?:,)')].freeze,
        ["MULT", Regexp.new('\\G(?:\\*)')].freeze,
        ["LINK", Regexp.new("\\G(?:#{JS_SPACE}*[xo<]?--+[-xo>]#{JS_SPACE}*)")].freeze,
        ["START_LINK", Regexp.new("\\G(?:#{JS_SPACE}*[xo<]?--#{JS_SPACE}*)")].freeze,
        ["LINK", Regexp.new("\\G(?:#{JS_SPACE}*[xo<]?==+[=xo>]#{JS_SPACE}*)")].freeze,
        ["START_LINK", Regexp.new("\\G(?:#{JS_SPACE}*[xo<]?==#{JS_SPACE}*)")].freeze,
        ["LINK", Regexp.new("\\G(?:#{JS_SPACE}*[xo<]?-?\\.+-[xo>]?#{JS_SPACE}*)")].freeze,
        ["START_LINK", Regexp.new("\\G(?:#{JS_SPACE}*[xo<]?-\\.#{JS_SPACE}*)")].freeze,
        ["LINK", Regexp.new("\\G(?:#{JS_SPACE}*~~[\\~]+#{JS_SPACE}*)")].freeze,
        ["(-", Regexp.new('\\G(?:\\(-)')].freeze,
        ["STADIUMSTART", Regexp.new('\\G(?:\\(\\[)')].freeze,
        ["SUBROUTINESTART", Regexp.new('\\G(?:\\[\\[)')].freeze,
        ["VERTEX_WITH_PROPS_START", Regexp.new('\\G(?:\\[\\|)')].freeze,
        ["TAGEND", Regexp.new('\\G(?:>)')].freeze,
        ["CYLINDERSTART", Regexp.new('\\G(?:\\[\\()')].freeze,
        ["DOUBLECIRCLESTART", Regexp.new('\\G(?:\\(\\(\\()')].freeze,
        ["TRAPSTART", Regexp.new('\\G(?:\\[\\/)')].freeze,
        ["INVTRAPSTART", Regexp.new('\\G(?:\\[\\\\)')].freeze,
        ["TAGSTART", Regexp.new('\\G(?:<)')].freeze,
        ["TAGEND", Regexp.new('\\G(?:>)')].freeze,
        ["UP", Regexp.new('\\G(?:\\^)')].freeze,
        ["SEP", Regexp.new('\\G(?:\\\\\\|)')].freeze,
        ["DOWN", Regexp.new("\\G(?:v#{ASCII_WORD_END})")].freeze,
        ["MULT", Regexp.new('\\G(?:\\*)')].freeze,
        ["BRKT", Regexp.new('\\G(?:#)')].freeze,
        ["AMP", Regexp.new('\\G(?:&)')].freeze,
        ["NODE_STRING", Regexp.new('\\G(?:([A-Za-z0-9!"\\#$%&\'*+\\.`?\\\\_\\/]|-(?=[^\\>\\-\\.])|(?!))+)')].freeze,
        ["MINUS", Regexp.new('\\G(?:-)')].freeze,
        ["UNICODE_TEXT", Regexp.new('\\G(?:[\\u00AA\\u00B5\\u00BA\\u00C0-\\u00D6\\u00D8-\\u00F6]|[\\u00F8-\\u02C1\\u02C6-\\u02D1\\u02E0-\\u02E4\\u02EC\\u02EE\\u0370-\\u0374\\u0376\\u0377]|[\\u037A-\\u037D\\u0386\\u0388-\\u038A\\u038C\\u038E-\\u03A1\\u03A3-\\u03F5]|[\\u03F7-\\u0481\\u048A-\\u0527\\u0531-\\u0556\\u0559\\u0561-\\u0587\\u05D0-\\u05EA]|[\\u05F0-\\u05F2\\u0620-\\u064A\\u066E\\u066F\\u0671-\\u06D3\\u06D5\\u06E5\\u06E6\\u06EE]|[\\u06EF\\u06FA-\\u06FC\\u06FF\\u0710\\u0712-\\u072F\\u074D-\\u07A5\\u07B1\\u07CA-\\u07EA]|[\\u07F4\\u07F5\\u07FA\\u0800-\\u0815\\u081A\\u0824\\u0828\\u0840-\\u0858\\u08A0]|[\\u08A2-\\u08AC\\u0904-\\u0939\\u093D\\u0950\\u0958-\\u0961\\u0971-\\u0977]|[\\u0979-\\u097F\\u0985-\\u098C\\u098F\\u0990\\u0993-\\u09A8\\u09AA-\\u09B0\\u09B2]|[\\u09B6-\\u09B9\\u09BD\\u09CE\\u09DC\\u09DD\\u09DF-\\u09E1\\u09F0\\u09F1\\u0A05-\\u0A0A]|[\\u0A0F\\u0A10\\u0A13-\\u0A28\\u0A2A-\\u0A30\\u0A32\\u0A33\\u0A35\\u0A36\\u0A38\\u0A39]|[\\u0A59-\\u0A5C\\u0A5E\\u0A72-\\u0A74\\u0A85-\\u0A8D\\u0A8F-\\u0A91\\u0A93-\\u0AA8]|[\\u0AAA-\\u0AB0\\u0AB2\\u0AB3\\u0AB5-\\u0AB9\\u0ABD\\u0AD0\\u0AE0\\u0AE1\\u0B05-\\u0B0C]|[\\u0B0F\\u0B10\\u0B13-\\u0B28\\u0B2A-\\u0B30\\u0B32\\u0B33\\u0B35-\\u0B39\\u0B3D\\u0B5C]|[\\u0B5D\\u0B5F-\\u0B61\\u0B71\\u0B83\\u0B85-\\u0B8A\\u0B8E-\\u0B90\\u0B92-\\u0B95\\u0B99]|[\\u0B9A\\u0B9C\\u0B9E\\u0B9F\\u0BA3\\u0BA4\\u0BA8-\\u0BAA\\u0BAE-\\u0BB9\\u0BD0]|[\\u0C05-\\u0C0C\\u0C0E-\\u0C10\\u0C12-\\u0C28\\u0C2A-\\u0C33\\u0C35-\\u0C39\\u0C3D]|[\\u0C58\\u0C59\\u0C60\\u0C61\\u0C85-\\u0C8C\\u0C8E-\\u0C90\\u0C92-\\u0CA8\\u0CAA-\\u0CB3]|[\\u0CB5-\\u0CB9\\u0CBD\\u0CDE\\u0CE0\\u0CE1\\u0CF1\\u0CF2\\u0D05-\\u0D0C\\u0D0E-\\u0D10]|[\\u0D12-\\u0D3A\\u0D3D\\u0D4E\\u0D60\\u0D61\\u0D7A-\\u0D7F\\u0D85-\\u0D96\\u0D9A-\\u0DB1]|[\\u0DB3-\\u0DBB\\u0DBD\\u0DC0-\\u0DC6\\u0E01-\\u0E30\\u0E32\\u0E33\\u0E40-\\u0E46\\u0E81]|[\\u0E82\\u0E84\\u0E87\\u0E88\\u0E8A\\u0E8D\\u0E94-\\u0E97\\u0E99-\\u0E9F\\u0EA1-\\u0EA3]|[\\u0EA5\\u0EA7\\u0EAA\\u0EAB\\u0EAD-\\u0EB0\\u0EB2\\u0EB3\\u0EBD\\u0EC0-\\u0EC4\\u0EC6]|[\\u0EDC-\\u0EDF\\u0F00\\u0F40-\\u0F47\\u0F49-\\u0F6C\\u0F88-\\u0F8C\\u1000-\\u102A]|[\\u103F\\u1050-\\u1055\\u105A-\\u105D\\u1061\\u1065\\u1066\\u106E-\\u1070\\u1075-\\u1081]|[\\u108E\\u10A0-\\u10C5\\u10C7\\u10CD\\u10D0-\\u10FA\\u10FC-\\u1248\\u124A-\\u124D]|[\\u1250-\\u1256\\u1258\\u125A-\\u125D\\u1260-\\u1288\\u128A-\\u128D\\u1290-\\u12B0]|[\\u12B2-\\u12B5\\u12B8-\\u12BE\\u12C0\\u12C2-\\u12C5\\u12C8-\\u12D6\\u12D8-\\u1310]|[\\u1312-\\u1315\\u1318-\\u135A\\u1380-\\u138F\\u13A0-\\u13F4\\u1401-\\u166C]|[\\u166F-\\u167F\\u1681-\\u169A\\u16A0-\\u16EA\\u1700-\\u170C\\u170E-\\u1711]|[\\u1720-\\u1731\\u1740-\\u1751\\u1760-\\u176C\\u176E-\\u1770\\u1780-\\u17B3\\u17D7]|[\\u17DC\\u1820-\\u1877\\u1880-\\u18A8\\u18AA\\u18B0-\\u18F5\\u1900-\\u191C]|[\\u1950-\\u196D\\u1970-\\u1974\\u1980-\\u19AB\\u19C1-\\u19C7\\u1A00-\\u1A16]|[\\u1A20-\\u1A54\\u1AA7\\u1B05-\\u1B33\\u1B45-\\u1B4B\\u1B83-\\u1BA0\\u1BAE\\u1BAF]|[\\u1BBA-\\u1BE5\\u1C00-\\u1C23\\u1C4D-\\u1C4F\\u1C5A-\\u1C7D\\u1CE9-\\u1CEC]|[\\u1CEE-\\u1CF1\\u1CF5\\u1CF6\\u1D00-\\u1DBF\\u1E00-\\u1F15\\u1F18-\\u1F1D]|[\\u1F20-\\u1F45\\u1F48-\\u1F4D\\u1F50-\\u1F57\\u1F59\\u1F5B\\u1F5D\\u1F5F-\\u1F7D]|[\\u1F80-\\u1FB4\\u1FB6-\\u1FBC\\u1FBE\\u1FC2-\\u1FC4\\u1FC6-\\u1FCC\\u1FD0-\\u1FD3]|[\\u1FD6-\\u1FDB\\u1FE0-\\u1FEC\\u1FF2-\\u1FF4\\u1FF6-\\u1FFC\\u2071\\u207F]|[\\u2090-\\u209C\\u2102\\u2107\\u210A-\\u2113\\u2115\\u2119-\\u211D\\u2124\\u2126\\u2128]|[\\u212A-\\u212D\\u212F-\\u2139\\u213C-\\u213F\\u2145-\\u2149\\u214E\\u2183\\u2184]|[\\u2C00-\\u2C2E\\u2C30-\\u2C5E\\u2C60-\\u2CE4\\u2CEB-\\u2CEE\\u2CF2\\u2CF3]|[\\u2D00-\\u2D25\\u2D27\\u2D2D\\u2D30-\\u2D67\\u2D6F\\u2D80-\\u2D96\\u2DA0-\\u2DA6]|[\\u2DA8-\\u2DAE\\u2DB0-\\u2DB6\\u2DB8-\\u2DBE\\u2DC0-\\u2DC6\\u2DC8-\\u2DCE]|[\\u2DD0-\\u2DD6\\u2DD8-\\u2DDE\\u2E2F\\u3005\\u3006\\u3031-\\u3035\\u303B\\u303C]|[\\u3041-\\u3096\\u309D-\\u309F\\u30A1-\\u30FA\\u30FC-\\u30FF\\u3105-\\u312D]|[\\u3131-\\u318E\\u31A0-\\u31BA\\u31F0-\\u31FF\\u3400-\\u4DB5\\u4E00-\\u9FCC]|[\\uA000-\\uA48C\\uA4D0-\\uA4FD\\uA500-\\uA60C\\uA610-\\uA61F\\uA62A\\uA62B]|[\\uA640-\\uA66E\\uA67F-\\uA697\\uA6A0-\\uA6E5\\uA717-\\uA71F\\uA722-\\uA788]|[\\uA78B-\\uA78E\\uA790-\\uA793\\uA7A0-\\uA7AA\\uA7F8-\\uA801\\uA803-\\uA805]|[\\uA807-\\uA80A\\uA80C-\\uA822\\uA840-\\uA873\\uA882-\\uA8B3\\uA8F2-\\uA8F7\\uA8FB]|[\\uA90A-\\uA925\\uA930-\\uA946\\uA960-\\uA97C\\uA984-\\uA9B2\\uA9CF\\uAA00-\\uAA28]|[\\uAA40-\\uAA42\\uAA44-\\uAA4B\\uAA60-\\uAA76\\uAA7A\\uAA80-\\uAAAF\\uAAB1\\uAAB5]|[\\uAAB6\\uAAB9-\\uAABD\\uAAC0\\uAAC2\\uAADB-\\uAADD\\uAAE0-\\uAAEA\\uAAF2-\\uAAF4]|[\\uAB01-\\uAB06\\uAB09-\\uAB0E\\uAB11-\\uAB16\\uAB20-\\uAB26\\uAB28-\\uAB2E]|[\\uABC0-\\uABE2\\uAC00-\\uD7A3\\uD7B0-\\uD7C6\\uD7CB-\\uD7FB\\uF900-\\uFA6D]|[\\uFA70-\\uFAD9\\uFB00-\\uFB06\\uFB13-\\uFB17\\uFB1D\\uFB1F-\\uFB28\\uFB2A-\\uFB36]|[\\uFB38-\\uFB3C\\uFB3E\\uFB40\\uFB41\\uFB43\\uFB44\\uFB46-\\uFBB1\\uFBD3-\\uFD3D]|[\\uFD50-\\uFD8F\\uFD92-\\uFDC7\\uFDF0-\\uFDFB\\uFE70-\\uFE74\\uFE76-\\uFEFC]|[\\uFF21-\\uFF3A\\uFF41-\\uFF5A\\uFF66-\\uFFBE\\uFFC2-\\uFFC7\\uFFCA-\\uFFCF]|[\\uFFD2-\\uFFD7\\uFFDA-\\uFFDC])')].freeze,
        ["PIPE", Regexp.new('\\G(?:\\|)')].freeze,
        ["PS", Regexp.new('\\G(?:\\()')].freeze,
        ["SQS", Regexp.new('\\G(?:\\[)')].freeze,
        ["DIAMOND_START", Regexp.new('\\G(?:\\{)')].freeze,
        ["QUOTE", Regexp.new('\\G(?:")')].freeze,
        ["NEWLINE", Regexp.new('\\G(?:(\\r?\\n)+)')].freeze,
        ["SPACE", Regexp.new("\\G(?:#{JS_SPACE})")].freeze,
        ["EOF", Regexp.new('\\G(?:$)')].freeze
      ].freeze

      # Opens the "string" lexer condition with no `return`. `[^"]+` returns
      # a non-empty STR; the closing `["]` pops with no token, so an
      # immediately-closed `""` produces zero tokens — accepted alone, and
      # inside a curve as long as the curve has some other token too;
      # `scan` refuses a curve only when it ends up with no token at all.
      # Keep `["]`, not `"`: it must stay byte-identical to mermaid's own
      # rule or the match breaks.
      # Built via Regexp.new, not a `/\G(?:["])/` literal: RuboCop's
      # Style/RedundantRegexpCharacterClass only inspects regexp literals,
      # so this keeps the exact same pattern as RULES' own STRING_OPEN
      # entry above without a disable comment.
      STRING_OPEN_REGEXP = Regexp.new('\G(?:["])')
      STRING_BODY_REGEXP = /\G(?:[^"]+)/

      # The 13 token kinds a `styleComponent` value takes, per the
      # grammar's own "Expecting ..." error message, minus two measured
      # exceptions: MULT (`*red`) and UNICODE_TEXT (`é`) fire in this
      # lexer position but are refused by the grammar with that same
      # message. UNIT and PCT are named by the error but no INITIAL rule
      # ever returns them — kept for fidelity, they never fire.
      ALLOWED = Set[
        'SEMI', 'NEWLINE', 'SPACE', 'EOF', 'COLON', 'STYLE',
        'NUM', 'COMMA', 'NODE_STRING', 'UNIT', 'BRKT', 'PCT', 'MINUS'
      ].freeze

      # What a linkStyle curve name (`interpolate <here>`) takes — a
      # different production (`alphaNum`), measured directly off the
      # grammar's own error message for `linkStyle 0 interpolate end`:
      # `Expecting 'DIR', 'AMP', 'COLON', 'DOWN', 'NUM', 'COMMA',
      # 'NODE_STRING', 'BRKT', 'MINUS', 'MULT', 'UNICODE_TEXT'`. DIR is
      # kept for fidelity; no INITIAL rule ever returns it (it belongs to
      # a different lexer condition entered only inside a subgraph
      # `direction` line), so it never fires here either.
      CURVE_ALLOWED = Set[
        'DIR', 'AMP', 'COLON', 'DOWN', 'NUM', 'COMMA',
        'NODE_STRING', 'BRKT', 'MINUS', 'MULT', 'UNICODE_TEXT'
      ].freeze

      # The two tokens that end a scan outright: NEWLINE because a
      # rebuilt statement never has a second line, EOF because there is
      # nothing left to read.
      TERMINAL_TOKENS = Set['NEWLINE', 'EOF'].freeze

      # `scan`'s own sentinels for "no rule matched" and "a rule matched
      # with no token", not mermaid token names — kept out of the
      # caller's hands via `unlexable?` below, so a rename or a third
      # sentinel here cannot silently fall through to a wrong message.
      UNLEXABLE = Set['NO_MATCH', 'STATE_SWITCH'].freeze

      private_constant :RULES, :STRING_OPEN_REGEXP, :STRING_BODY_REGEXP, :ALLOWED, :CURVE_ALLOWED,
                       :STYLE_RUN, :CLASS_DEF_RUN, :ENTITY, :TERMINAL_TOKENS, :ASCII_WORD_END,
                       :UNLEXABLE, :JS_SPACE_CHARS, :JS_DOT

      # True for a `refusal` token that names one of `scan`'s own
      # sentinels rather than a real mermaid token — the caller's cue to
      # say "mermaid's lexer cannot read it" instead of naming a token
      # that does not exist in mermaid's own grammar.
      def self.unlexable?(token)
        UNLEXABLE.include?(token)
      end

      # `encodeEntities`, ported exactly.
      def self.prepass(text)
        strip_glued_semicolons(text).gsub(ENTITY) do |s|
          inner = s[1..-2]
          is_int = inner =~ /\A\+?\d+\z/
          is_int ? "\u{FB02}\u{B0}\u{B0}#{inner}\u{B6}\u{DF}" : "\u{FB02}\u{B0}#{inner}\u{B6}\u{DF}"
        end
      end
      private_class_method :prepass

      # The entity a `linkStyle` line would be left holding after the same
      # style/classDef gluing runs but before the substitution itself —
      # used only to name the offending text in `check_link_entities`'s
      # own error message; `prepass` above does the actual substitution
      # for the allowlist scan.
      def self.entity(text)
        strip_glued_semicolons(text)[ENTITY]
      end

      # The one shape `prepass` and `entity` both need first: drop the
      # trailing `;` that `style`/`classDef` glue onto a hashed run, the
      # same way and in the same order `encodeEntities` does, before
      # either one goes looking for `#name;` on what is left.
      def self.strip_glued_semicolons(text)
        text.sub(STYLE_RUN) { |s| s[0..-2] }.sub(CLASS_DEF_RUN) { |s| s[0..-2] }
      end
      private_class_method :strip_glued_semicolons

      # `keyword` names the statement in the error message and, for
      # `style`/`classDef`, is also the literal text mermaid's own entity
      # pre-pass looks for (`style.*:\S*#.*;`, `classDef.*:\S*#.*;`) — real
      # target text does not matter to that regex, so a fixed bait word is
      # enough to reproduce the same gluing. `linkStyle` never matches
      # either pattern (capital S), so its bait is inert and only `curve`
      # plus `props` are scanned, against `CURVE_ALLOWED` and `ALLOWED`
      # respectively.
      #
      # Returns `[matched_text, token_name]` when mermaid's lexer would
      # refuse the value, or `nil` when every token is allowed.
      def self.refusal(keyword, props, curve: nil)
        head = "#{keyword} "
        scan_start = head.length
        curve_end = curve ? scan_start + curve.to_s.length : nil
        body = curve ? "#{curve} #{props}" : props

        scan(prepass("#{head}#{body}\n"), scan_start, curve_end)
      end

      # LINK_ID, LINK/START_LINK and `direction_*` are greedy and unbounded,
      # so a presence check at `scan_start` does not bound their cost: a
      # trigger past a JS line terminator keeps every rule retried at every
      # position. Keep `TriggerReach` (occurrence lists walked forward only)
      # for all three; a plain occurrence check reintroduces the quadratic cost.
      LINK_TOKENS = Set['LINK', 'START_LINK'].freeze
      DIRECTION_TOKENS = Set[
        'direction_tb', 'direction_bt', 'direction_rl', 'direction_lr', 'direction_td'
      ].freeze
      private_constant :LINK_TOKENS, :DIRECTION_TOKENS

      # Two cursors over precomputed, sorted BYTE-offset occurrence lists,
      # walked forward only — `reachable?` costs O(1) amortized only when
      # called with a non-decreasing `byte_pos` sequence, as `scan`'s loop
      # does; do not call it out of order.
      # Byte, not character, offsets: `MatchData#begin`/`byteoffset` cost
      # O(current offset) once `text` holds any multibyte character, and a
      # value with the NBSP `JS_SPACE` limit can hit that thousands of
      # times — `byteoffset` alone avoids it. `byte_scan_start` needs no
      # conversion because `head` is always ASCII.
      class TriggerReach
        def initialize(text, byte_scan_start, trigger_regexp, limit_regexp)
          @triggers = occurrences(text, trigger_regexp, byte_scan_start)
          @limits = occurrences(text, limit_regexp, byte_scan_start)
          @trigger_cursor = 0
          @limit_cursor = 0
        end

        # Skipping either advance below only ever makes this return MORE
        # permissively true, never wrongly false — `scan` always ANDs this
        # with a real `scanner.match?` attempt before a rule can win, so the
        # worst case is one wasted failed attempt. Keep the advances anyway:
        # they are what makes this O(1) amortized, not just output-safe.
        # This cannot fix a wrong TRIGGER or LIMIT regex, only stay faithful
        # to it — see `LINK_LIMIT`'s own comment for the shape of bug that
        # produces.
        def reachable?(byte_pos)
          @trigger_cursor += 1 while behind?(@triggers, @trigger_cursor, byte_pos)
          @limit_cursor += 1 while behind?(@limits, @limit_cursor, byte_pos)
          next_trigger = @triggers[@trigger_cursor]
          return false unless next_trigger

          next_limit = @limits[@limit_cursor]
          next_limit.nil? || next_trigger < next_limit
        end

        private

        def behind?(positions, cursor, byte_pos)
          cursor < positions.length && positions[cursor] < byte_pos
        end

        def occurrences(text, regexp, byte_scan_start)
          found = []
          text.scan(regexp) do
            byte_begin = ::Regexp.last_match.byteoffset(0)[0]
            found << byte_begin if byte_begin >= byte_scan_start
          end
          found
        end
      end
      private_constant :TriggerReach

      # Not bare `@`: LINK_ID's own regex is `[^\s"]+@(?=[^{"])`, so an `@`
      # immediately followed by `{` or `"` can never complete a match —
      # counting it as a trigger anyway searches the rest of the value for
      # a completion that was never going to work, backtracking off a long
      # non-space run at every position before it (measured: 20k reps of
      # `"a,"` before an `a@{` tail cost 5.7s gated on bare `@`, versus
      # linear once the lookahead is part of the trigger).
      LINK_ID_TRIGGER = /@(?=[^{"])/
      LINK_ID_LIMIT = /#{JS_SPACE}|"/
      LINK_TRIGGER = /[-=~]/
      # Not `JS_SPACE` alone: all seven LINK/START_LINK rules in `RULES`
      # start with `JS_SPACE*`, so a space or NBSP sitting right before the
      # trigger is legal prefix text the rule still accepts, not something
      # that ends the run. Counting it as a limit made `reachable?` return
      # false at exactly the position mermaid's lexer would take (measured:
      # `style A fill:a --b@c` gated LINK_ID's `--b@` in instead of the
      # arrow's own `--`), which changed which rule won, not just whether
      # an attempt was wasted. `xo<.=~-` covers the rest of what those
      # seven rules accept before their own trigger character; anything
      # else really does end the run.
      LINK_LIMIT = /[^#{JS_SPACE_CHARS}xo<.=~-]/
      DIRECTION_COMPLETE = /direction#{JS_SPACE}+(?:TB|BT|RL|LR|TD)/
      # `direction_*`'s own `#{JS_DOT}*` leading span (see the RULES entries
      # below) cannot cross a JS line terminator, so a complete pattern past
      # one can never be what any of the five rules match from an earlier
      # position — gating on a single whole-text `DIRECTION_COMPLETE` check
      # (as `scan` used to) kept them "active" for every position up to a
      # terminator anyway, and each of the five retried its full greedy scan
      # at every one of those positions: O(run length) work times O(run
      # length) positions. `DIRECTION_LIMIT` bounds the trigger the same way
      # `LINK_LIMIT`/`LINK_ID_LIMIT` already bound theirs, so `reachable?`
      # answers "is a complete pattern still ahead of pos, before the next
      # terminator" in amortized O(1) instead.
      DIRECTION_TRIGGER = DIRECTION_COMPLETE
      DIRECTION_LIMIT = /[\n\r  ]/

      # What `scan` uses to measure a run it has already found dead for
      # LINK/START_LINK (see `link_dead_until` there): every LINK/START_LINK
      # regex in `RULES` starts with `JS_SPACE*`, so at any position within
      # one contiguous run of `JS_SPACE` characters that leading piece always
      # consumes forward to the same run end, whichever position it starts
      # from — this measures that same end directly.
      JS_SPACE_RUN = /\G#{JS_SPACE}*/
      private_constant :LINK_ID_TRIGGER, :LINK_ID_LIMIT, :LINK_TRIGGER, :LINK_LIMIT, :DIRECTION_COMPLETE,
                       :DIRECTION_TRIGGER, :DIRECTION_LIMIT, :JS_SPACE_RUN

      # `token` names a rule from `RULES`; the three booleans are each
      # already resolved for the current `pos` — all three per position,
      # not once for the whole scan — kept as plain booleans, not
      # `TriggerReach` objects, so this stays a cheap lookup with no
      # allocation, called once per rule tried.
      def self.active?(token, link_id_active, link_active, direction_active)
        return link_id_active if token == 'LINK_ID'
        return link_active if LINK_TOKENS.include?(token)
        return direction_active if DIRECTION_TOKENS.include?(token)

        true
      end
      private_class_method :active?

      # From `scan_start` to the end of `text` (already prepassed), returns
      # the first token whose symbol is not allowed for its position, or
      # `nil` when every token is allowed. `curve_end`, when given, splits
      # checking: before it against `CURVE_ALLOWED`, after against
      # `ALLOWED`, scanned as one continuous pass because `direction_*`
      # looks ahead to the line's end.
      #
      # `byte_pos` mirrors `pos` in bytes and positions a `StringScanner`
      # directly, avoiding the O(pos)-per-call cost of resolving a
      # character `pos` once `text` holds a multibyte character — the same
      # quadratic blowup `TriggerReach` exists to avoid.
      def self.scan(text, scan_start, curve_end)
        pos = scan_start
        byte_pos = scan_start
        scanner = StringScanner.new(text)
        link_id_reach = TriggerReach.new(text, scan_start, LINK_ID_TRIGGER, LINK_ID_LIMIT)
        link_reach = TriggerReach.new(text, scan_start, LINK_TRIGGER, LINK_LIMIT)
        direction_reach = TriggerReach.new(text, scan_start, DIRECTION_TRIGGER, DIRECTION_LIMIT)
        curve_tokenless = curve_end ? true : false
        # Byte offset up to which LINK/START_LINK are already known to fail —
        # see `JS_SPACE_RUN`'s comment for why one failed attempt inside a
        # whitespace run proves every later position in the same run also
        # fails, and set below the moment that happens.
        link_dead_until = -1
        while pos < text.length
          # Every `CURVE_ALLOWED` rule matches wholly inside the curve's own
          # non-space run, so `pos` lands exactly on `curve_end` the moment
          # the curve is done — keep that true, or this stops firing.
          return [text[scan_start...curve_end], 'STR'] if pos == curve_end && curve_tokenless

          link_id_active = link_id_reach.reachable?(byte_pos)
          link_active = byte_pos >= link_dead_until && link_reach.reachable?(byte_pos)
          direction_active = direction_reach.reachable?(byte_pos)
          scanner.pos = byte_pos
          rule = RULES.find do |(token, regexp)|
            active?(token, link_id_active, link_active, direction_active) && scanner.match?(regexp)
          end
          return [text[pos..], 'NO_MATCH'] unless rule

          token = rule.first
          # Captured immediately, before the `JS_SPACE_RUN` probe below runs
          # its own `scanner.match?` — that call overwrites `scanner`'s
          # matched state too, so reading `.matched` any later would return
          # the probe's span instead of the rule that actually won here.
          matched = scanner.matched

          # `scanner.pos` is still `byte_pos` here (`match?` never advances
          # it), so this measures the run starting exactly where the failed
          # attempts above just tried and gives back 0 when `byte_pos` is not
          # itself a space character — safe to run unconditionally.
          if link_active && !LINK_TOKENS.include?(token)
            scanner.match?(JS_SPACE_RUN)
            link_dead_until = byte_pos + scanner.matched_size
          end

          if token == :STRING_OPEN
            matched, next_pos, next_byte_pos = scan_string_body(scanner, pos + 1, byte_pos + 1)
            return [text[pos...next_pos], 'STR'] if matched

            pos = next_pos
            byte_pos = next_byte_pos
            next
          end

          in_curve = curve_end && pos < curve_end
          allowed = in_curve ? CURVE_ALLOWED : ALLOWED
          return [matched, token || 'STATE_SWITCH'] unless token && allowed.include?(token)

          curve_tokenless = false if in_curve

          # `declaration_char` (the grammar rule every `props`/`curve`
          # comes from) excludes `line_end`, so `.refusal` itself never
          # passes an embedded newline — but `scan` is the private worker,
          # not the public entry point, and a direct call with one (see
          # the "stops at the first embedded NEWLINE" spec) proves this
          # break IS load-bearing: without it NEWLINE falls through to
          # whatever rule matches next instead of ending the scan there.
          break if TERMINAL_TOKENS.include?(token)

          pos += matched.length
          byte_pos += matched.bytesize
        end
      end
      private_class_method :scan

      # Simulates the "string" lexer condition entered by `STRING_OPEN_REGEXP`:
      # any run of non-quote characters is one STR token, then the closing
      # quote pops back to INITIAL with no token of its own. Returns
      # `[matched_str_or_nil, position_after_the_closing_quote,
      # byte_position_after_the_closing_quote]`; `nil` for an
      # immediately-closed `""`, which produces no token at all. The
      # closing quote is always 1 byte (`"` is ASCII), so `byte_pos`
      # advances by 1 alongside `pos` in the empty-pair case.
      def self.scan_string_body(scanner, pos, byte_pos)
        scanner.pos = byte_pos
        if scanner.match?(STRING_OPEN_REGEXP)
          [nil, pos + 1, byte_pos + 1] # empty pair, no token
        elsif scanner.match?(STRING_BODY_REGEXP)
          matched = scanner.matched
          [matched, pos + matched.length, byte_pos + matched.bytesize]
        else
          ['', pos, byte_pos] # ran out of input mid-string; treat as a refusal below
        end
      end
      private_class_method :scan_string_body
    end
  end
end
