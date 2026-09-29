# frozen_string_literal: true

require "spec_helper"

# Every verdict below matches mermaid 11.12.0: run `mermaid.parse` on
# "graph TD\nA-->B\n" followed by the row's statement. A row that disagrees
# with that call is wrong, whatever sirena does.
RSpec.describe Sirena::Parser::Flowchart do
  include FlowchartParserHelpers

  let(:header) { "graph TD\nA-->B\n" }

  describe "a style, classDef or linkStyle value mermaid's lexer cannot read" do
    # `keyword` is the word `check_style_text` puts in its own error message
    # ("style"/"classDef"/"linkStyle"), not the full statement prefix
    # ("style A"/"classDef c1"/"linkStyle 0") — the two only coincide for
    # `linkStyle`. `matched`/`reason` are the exact text and phrase
    # `FlowchartStyleText.refusal` and `check_style_text` produce for that
    # value under all three keywords (verified identical: none of these
    # values hits the style/classDef-only entity gluing that could make the
    # three diverge), pinned here rather than matched loosely so a swapped
    # token name or a re-widened NO_MATCH/STATE_SWITCH message goes red.
    all_prefixes = { "style A" => "style", "classDef c1" => "classDef", "linkStyle 0" => "linkStyle" }.freeze

    {
      "a bare `end` keyword" => ["fill:red end", "end", "mermaid reads it as end"],
      "`click` followed by another word" => ["fill:red click x", "click", "mermaid's lexer cannot read it"],
      "`call` followed by another word" => ["fill:red call x", "call", "mermaid's lexer cannot read it"],
      "`href` followed by another word" => ["fill:red href x", "href", "mermaid reads it as HREF"],
      "a trailing `click` with nothing after it" => ["fill:red click", "click", "mermaid's lexer cannot read it"],
      "a trailing `call` with nothing after it" => ["fill:red call", "call", "mermaid's lexer cannot read it"],
      "a trailing `href` with nothing after it" => ["fill:red href", "href", "mermaid reads it as HREF"],
      "an `accTitle:` directive" => ["accTitle:x", "accTitle:", "mermaid reads it as acc_title"],
      "an arrow" => ["fill:a-->b", "-->", "mermaid reads it as LINK"],
      "a `<` tag start" => ["fill:a<b", "<", "mermaid reads it as TAGSTART"],
      "an `@` shape-data id" => ["fill:a@b", "fill:a@", "mermaid reads it as LINK_ID"],
      "a `:::` style separator" => ["fill:a:::b", ":::", "mermaid reads it as STYLE_SEPARATOR"],
      "a `(`" => ["fill:a(b)", "(", "mermaid reads it as PS"],
      "a quoted string" => ['fill:"red"', "\"red", "mermaid reads it as STR"],
      "a `*` (MULT)" => ["fill:*red", "*", "mermaid reads it as MULT"],
      "non-ASCII text (UNICODE_TEXT)" => ["fill:é", "é", "mermaid reads it as UNICODE_TEXT"],
      "a `direction TB` line" => ["fill:red direction TB", "fill:red direction TB", "mermaid reads it as direction_tb"],
      "a doubled `#` prefix" => ["fill:##end", "end", "mermaid reads it as end"],
      "a digit before the `#`" => ["fill:1#2end", "end", "mermaid reads it as end"],
      "rgba()" => ["fill:rgba(0,0,0,0.5)", "(", "mermaid reads it as PS"],
      # Rule 101 of the live bundle (`\\|`) is SEP, not the bare-`|` rules'
      # PIPE — pins the relabel: a mismatched token name here means the two
      # regexes were confused again.
      "an escaped pipe (SEP, not PIPE)" => ['fill:\|', '\|', "mermaid reads it as SEP"]
    }.each do |description, (value, matched, reason)|
      all_prefixes.each do |prefix, keyword|
        it "refuses #{description} in `#{prefix} #{value}` naming `#{matched}` and `#{reason}`" do
          expect { parse_flowchart("#{prefix} #{value}", header: header) }
            .to raise_error(Sirena::Parser::ParseError, "#{keyword} cannot use `#{matched}` in its styles: #{reason}.")
        end
      end
    end
  end

  describe "a linkStyle curve name" do
    {
      "end" => ["end", "end", "mermaid reads it as end"],
      "style" => ["style", "style", "mermaid reads it as STYLE"],
      "graph" => ["graph", "graph", "mermaid reads it as GRAPH"],
      "href" => ["href", "href", "mermaid reads it as HREF"],
      "call" => ["call", "call", "mermaid's lexer cannot read it"],
      "click" => ["click", "click", "mermaid's lexer cannot read it"],
      "a direction TB line" => ["direction TB", "direction TB", "mermaid reads it as direction_tb"],
      # Accepted as a props value (see "an empty quoted pair" below, in the
      # look-alike section) — refused only here, because a curve name must
      # produce at least one token and an immediately-closed pair produces
      # none.
      "an empty quoted pair" => ['""', '""', "mermaid reads it as STR"]
    }.each do |description, (curve, matched, reason)|
      it "refuses #{description} naming `#{matched}` and `#{reason}`" do
        expect { parse_flowchart("linkStyle 0 interpolate #{curve}", header: header) }
          .to raise_error(Sirena::Parser::ParseError, "linkStyle cannot use `#{matched}` in its styles: #{reason}.")
      end
    end

    {
      "`*`" => "*",
      "non-ASCII text" => "é",
      "a real curve name" => "basis",
      # `&` and `#` are also NODE_STRING characters, so a curve value that
      # only embeds them mid-word (`a&b`) never isolates the standalone
      # AMP/BRKT rule at all — NODE_STRING's own `+` swallows the whole
      # run first. Only a curve that is just the bare character reaches
      # the earlier, separate AMP/BRKT rule.
      "`&`" => "&",
      "`v`" => "v",
      "`:`" => "a:b",
      "`,`" => "a,b",
      "`#`" => "#",
      "a number" => "5",
      # An empty quoted pair next to a real token is not a zero-token
      # curve — only a curve that is nothing BUT empty pairs is refused
      # (see the "empty quoted pair" refusals above).
      "an empty quoted pair before a real token" => '""-',
      "an empty quoted pair before a curve name" => '""basis',
      "an empty quoted pair after a real token" => ':""'
    }.each do |description, curve|
      it "takes #{description}" do
        expect(parse_flowchart("linkStyle 0 interpolate #{curve}", header: header).edges.size).to eq(1)
      end
    end

    # `MULT`, `UNICODE_TEXT`, `AMP` and `DOWN` are in `CURVE_ALLOWED` but not
    # `ALLOWED` — the split `CURVE_ALLOWED`/`ALLOWED` exist for. Each is
    # accepted as a curve name above; here the same bare value is refused as
    # a props value, proving the split runs both ways, not just the one
    # direction the "takes" table above already covers.
    {
      "`*` (MULT)" => ["*", "*", "mermaid reads it as MULT"],
      "non-ASCII text (UNICODE_TEXT)" => ["é", "é", "mermaid reads it as UNICODE_TEXT"],
      "`&` (AMP)" => ["&", "&", "mermaid reads it as AMP"],
      "`v` (DOWN)" => ["v", "v", "mermaid reads it as DOWN"]
    }.each do |description, (value, matched, reason)|
      it "refuses #{description} as a `style` props value naming `#{matched}` and `#{reason}`" do
        expect { parse_flowchart("style A #{value}", header: header) }
          .to raise_error(Sirena::Parser::ParseError, "style cannot use `#{matched}` in its styles: #{reason}.")
      end
    end
  end

  describe "a linkStyle curve followed by props" do
    # The curve/props split (`CURVE_ALLOWED` before `curve_end`, `ALLOWED`
    # from there on) is otherwise only exercised with the curve alone
    # (empty props) or the props alone (no curve) — never both in the same
    # statement, so the boundary itself was never pinned where a real props
    # value follows a real curve. `v`/`*`/`&`/`é` are each `CURVE_ALLOWED`
    # but not `ALLOWED`, so each proves the boundary still holds once
    # `curve_end` is reached, not just that a bare curve or a bare props
    # value is checked correctly on its own.
    {
      "`v` (DOWN)" => ["v", "v", "mermaid reads it as DOWN"],
      "`*` (MULT)" => ["*", "*", "mermaid reads it as MULT"],
      "`&` (AMP)" => ["&", "&", "mermaid reads it as AMP"],
      "non-ASCII text (UNICODE_TEXT)" => ["é", "é", "mermaid reads it as UNICODE_TEXT"]
    }.each do |description, (value, matched, reason)|
      it "refuses #{description} in the props that follow a real curve, naming `#{matched}` and `#{reason}`" do
        expect { parse_flowchart("linkStyle 0 interpolate basis fill:#{value}", header: header) }
          .to raise_error(Sirena::Parser::ParseError, "linkStyle cannot use `#{matched}` in its styles: #{reason}.")
      end
    end
  end

  describe "look-alike text a style, classDef or linkStyle value takes" do
    all_prefixes = ["style A", "classDef c1", "linkStyle 0"].freeze
    # Only `style` and `classDef` get the last-`;` gluing that removes the
    # semicolon before mermaid's lexer ever sees it (`FlowchartStyleText
    # ::STYLE_RUN`/`::CLASS_DEF_RUN`); `linkStyle` does not, so
    # `linkStyle 0 fill:#f9f;end` keeps its semicolon and is refused
    # instead — as an HTML entity, by the existing `check_link_entities`,
    # covered in flowchart_parser_link_style_spec.rb.
    style_and_classdef = ["style A", "classDef c1"].freeze

    {
      "a word that starts with a keyword" => ["fill:endless", all_prefixes],
      "a word that ends with a keyword" => ["fill:backend", all_prefixes],
      "a keyword spelled with a different case" => ["fill:End", all_prefixes],
      "`href` with no trailing space" => ["fill:hrefs", all_prefixes],
      "the literal word `style`, itself an allowed token" => ["fill:style", all_prefixes],
      "`direction` with no TB/BT/RL/LR/TD after it" => ["fill:direction", all_prefixes],
      "a quote embedded mid-word" => ['fill:a"b', all_prefixes],
      "an empty quoted pair" => ['fill:""', all_prefixes],
      "`end` glued onto the hashed value" => ["fill:#f9f;end", style_and_classdef],
      "`click` glued onto the hashed value" => ["fill:#f9f;click", style_and_classdef],
      "a hex colour" => ["fill:#f9f", all_prefixes],
      "a space-separated dasharray" => ["stroke-dasharray:5 5", all_prefixes],
      "a px unit" => ["font-size:12px", all_prefixes],
      "a percent unit" => ["opacity:50%", all_prefixes],
      "!important" => ["color:red !important", all_prefixes],
      "a comma-separated list" => ["stroke:red,stroke-width:2px", all_prefixes]
    }.each do |description, (value, prefixes)|
      prefixes.each do |prefix|
        it "takes #{description} in `#{prefix} #{value}`" do
          expect(parse_flowchart("#{prefix} #{value}", header: header).edges.size).to eq(1)
        end
      end
    end
  end

  describe "a style/classDef statement's own closing `;`, with a space before the `#`" do
    # The grammar's `hashed_head` only starts a hashed run at a `#` with no
    # preceding space, so `fill: #fff;` is plain `style_property` text and
    # its trailing `;` is the statement's own `statement_end`, not part of
    # `style_props`/`class_props` — the one case that terminator was never
    # being handed to `check_style_text` at all. mermaid still glues that
    # `;` onto the `#fff` right before it (`encodeEntities` runs on the
    # whole line), turning it into an entity placeholder and refusing.
    # `linkStyle` gets no such gluing (its own path already appends
    # `link_end` before this round — see flowchart_parser_link_style_spec.rb).
    {
      "style A" => "style",
      "classDef c1" => "classDef"
    }.each do |prefix, keyword|
      it "refuses `#{prefix} fill: #fff;` as a UNICODE_TEXT entity placeholder" do
        expect { parse_flowchart("#{prefix} fill: #fff;", header: header) }
          .to raise_error(Sirena::Parser::ParseError, "#{keyword} cannot use `ﬂ` in its styles: mermaid reads it as UNICODE_TEXT.")
      end

      it "refuses `#{prefix} #ab;` (no colon at all) the same way" do
        expect { parse_flowchart("#{prefix} #ab;", header: header) }
          .to raise_error(Sirena::Parser::ParseError, "#{keyword} cannot use `ﬂ` in its styles: mermaid reads it as UNICODE_TEXT.")
      end

      it "still refuses `#{prefix} fill: #fff;x`, with a node statement glued right after the `;`" do
        expect { parse_flowchart("#{prefix} fill: #fff;x", header: header) }
          .to raise_error(Sirena::Parser::ParseError, "#{keyword} cannot use `ﬂ` in its styles: mermaid reads it as UNICODE_TEXT.")
      end
    end
  end
end
