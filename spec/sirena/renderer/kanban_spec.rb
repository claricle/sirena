# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

# Single-user (this file only), pure — no let/expect/described_class.
module KanbanSpecHelpers
  module_function

  def layout_with(
    card_text:,
    column_title: "Todo",
    header_height: 50,
    **card_options
  )
    card_height = card_options.fetch(:card_height, 80)
    board_height = card_options.fetch(:board_height, 150)
    metadata = card_options.fetch(:metadata, {})
    has_metadata = card_options.fetch(:has_metadata, false)
    {
      columns: [
        {
          id: "todo",
          title: column_title,
          x: 0,
          y: 0,
          width: 200,
          height: board_height,
          header_height: header_height,
          card_count: 1,
        },
      ],
      cards: [
        {
          id: "card",
          text: card_text,
          column_id: "todo",
          x: 10,
          y: 60,
          width: 180,
          height: card_height,
          metadata: metadata,
          has_metadata: has_metadata,
        },
      ],
      width: 200,
      height: board_height,
    }
  end
end

module KanbanRendererSpecHelpers
  def rendered_layout(...)
    layout = KanbanSpecHelpers.layout_with(...)
    renderer.render(layout).to_xml
  end

  def first_xml_element(xml, path)
    REXML::XPath.first(REXML::Document.new(xml), path)
  end

  def expect_bold_card_run(xml)
    expect(xml).to match(%r{<tspan[^>]*font-weight="bold"[^>]*>urgent</tspan>})
    expect(xml).to include("<tspan>Hello </tspan>")
    expect(xml).not_to include("**")
  end

  def expect_escaped_styled_run(xml)
    expect(xml).to include('<tspan font-weight="bold">&lt;b&gt;&amp;"x</tspan>')
    expect(xml).not_to include("<b>")
    bold = first_xml_element(xml, '//tspan[@font-weight="bold"]')
    expect(bold.text).to eq('<b>&"x')
  end

  def expect_bold_header_runs(xml)
    expect(xml).to match(%r{<tspan[^>]*font-weight="bold"[^>]*>urgent</tspan>})
    expect(xml).to match(%r{<tspan[^>]*font-weight="bold"[^>]*>Todo </tspan>})
  end

  def line_y_positions(second_line)
    parent_attributes = second_line.parent.attributes
    actual = second_line.attributes["y"].to_f
    expected = parent_attributes["y"].to_f +
      (parent_attributes["font-size"].to_f * 1.2)
    [actual, expected]
  end

  def line_position(line_xml)
    second_line = first_xml_element(line_xml, '//tspan[text()="Line two"]')
    actual_y, expected_y = line_y_positions(second_line)
    [second_line.attributes["x"], actual_y, expected_y]
  end

  def expect_line_and_italic_attributes(line_xml, italic_xml)
    x, y, expected_y = line_position(line_xml)
    expect(x).to eq("60.0")
    expect(y).to be_within(0.001).of(expected_y)
    italic = first_xml_element(italic_xml, '//tspan[text()="urgent"]')
    expect(italic.attributes["font-style"]).to eq("italic")
  end

  def header_parts(xml, height)
    parsed = REXML::Document.new(xml)
    rect = REXML::XPath.first(parsed, "//rect[@height='#{height}.0']")
    text = REXML::XPath.first(parsed, "//text[tspan]")
    [rect, text, text.elements.to_a("tspan").size]
  end

  def header_baselines(text, count)
    font_size = text.attributes["font-size"].to_f
    first = text.attributes["y"].to_f
    [first, first + ((count - 1) * font_size * 1.2)]
  end

  def header_bounds(rect)
    top = rect.attributes["y"].to_f
    [top, top + rect.attributes["height"].to_f]
  end

  def expect_header_shape(rect, count, expected_count)
    expect(rect).not_to be_nil
    expect(count).to eq(expected_count)
  end

  def expect_three_line_header(xml)
    rect, text, count = header_parts(xml, 86)
    _, last = header_baselines(text, count)
    _, bottom = header_bounds(rect)
    expect_header_shape(rect, count, 3)
    expect(last).to be < bottom
  end

  def expect_four_line_baselines(first, last, top, bottom)
    expect(first).to eq(71.8)
    expect(last).to be_within(0.001).of(122.2)
    expect(last).to be < bottom
    expect(first).to be > top
  end

  def expect_four_line_header(xml)
    rect, text, count = header_parts(xml, 104)
    first, last = header_baselines(text, count)
    top, bottom = header_bounds(rect)
    expect_header_shape(rect, count, 4)
    expect_four_line_baselines(first, last, top, bottom)
  end

  def label_count_and_last_baseline(xml)
    label = first_xml_element(xml, "//text[tspan]")
    count = label.elements.to_a("tspan").size
    _, last = header_baselines(label, count)
    [count, last]
  end

  def expect_metadata_below_label(xml)
    count, last = label_count_and_last_baseline(xml)
    metadata = first_xml_element(xml, "//text[.='Assigned:']")
    metadata_y = metadata.attributes["y"].to_f
    expect(count).to eq(3)
    expect(metadata_y).to be > last
  end

  def bold_split_state(xml)
    parsed = REXML::Document.new(xml)
    first = REXML::XPath.first(parsed, '//tspan[text()="a"]')
    second = REXML::XPath.first(parsed, '//tspan[text()="b"]')
    parent_y = second.parent.attributes["y"].to_f
    [first.attributes["font-weight"], second.attributes["font-weight"],
     second.attributes["y"].to_f > parent_y]
  end
end

RSpec.describe Sirena::Renderer::Kanban do
  include KanbanRendererSpecHelpers

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe "#render" do
    context "with a simple kanban board" do
      let(:layout) do
        {
          columns: [
            {
              id: "todo",
              title: "Todo",
              x: 0,
              y: 0,
              width: 200,
              height: 150,
              header_height: 50,
              card_count: 1,
            },
          ],
          cards: [
            {
              id: "docs",
              text: "Create Documentation",
              column_id: "todo",
              x: 10,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false,
            },
          ],
          width: 200,
          height: 150,
        }
      end

      it "renders an SVG document" do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end

      it "includes column elements" do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include("rect", "Todo")
      end

      it "includes card elements" do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include("Create Documentation")
      end
    end

    context "with multiple columns" do
      let(:layout) do
        {
          columns: [
            {
              id: "todo",
              title: "Todo",
              x: 0,
              y: 0,
              width: 200,
              height: 150,
              header_height: 50,
              card_count: 1,
            },
            {
              id: "done",
              title: "Done",
              x: 260,
              y: 0,
              width: 200,
              height: 150,
              header_height: 50,
              card_count: 1,
            },
          ],
          cards: [
            {
              id: "docs",
              text: "Create Documentation",
              column_id: "todo",
              x: 10,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false,
            },
            {
              id: "release",
              text: "Release v1.0",
              column_id: "done",
              x: 270,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false,
            },
          ],
          width: 460,
          height: 150,
        }
      end

      it "renders all columns" do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include("Todo", "Done")
      end

      it "renders all cards" do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include("Create Documentation", "Release v1.0")
      end
    end

    context "with card metadata" do
      let(:layout) do
        {
          columns: [
            {
              id: "todo",
              title: "Todo",
              x: 0,
              y: 0,
              width: 200,
              height: 180,
              header_height: 50,
              card_count: 1,
            },
          ],
          cards: [
            {
              id: "docs",
              text: "Create Documentation",
              column_id: "todo",
              x: 10,
              y: 60,
              width: 180,
              height: 110,
              metadata: {
                priority: "High",
                ticket: "MC-1001",
              },
              has_metadata: true,
            },
          ],
          width: 200,
          height: 180,
        }
      end

      it "renders metadata" do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include("Priority", "High", "Ticket", "MC-1001")
      end
    end

    context "with empty board" do
      let(:layout) do
        {
          columns: [],
          cards: [],
          width: 0,
          height: 0,
        }
      end

      it "renders without errors" do
        expect { renderer.render(layout) }.not_to raise_error
      end
    end

    context "with markdown in card and column labels" do
      # Regression guard for the reported bug: mermaid renders `**urgent**`
      # as bold, sirena printed it literally. Mutation-check: revert
      # `render_card_text` to build `Svg::Text` with `t.content =
      # truncate_text(card[:text], 25)` directly (the pre-feature code).
      # Watched red: the assertions below fail — the literal `**` reappears
      # in the XML and no `<tspan font-weight="bold">` exists.
      it 'renders a bold card run as a <tspan font-weight="bold">, ' \
         "with no literal markers" do
        xml = rendered_layout(card_text: "Hello **urgent**")
        expect_bold_card_run(xml)
      end

      # A bold run wider than the card wraps into bold tspans and keeps every
      # character; it must not be cut or leave a stray marker.
      it "wraps a long bold run into bold tspans without losing a character" do
        long_text = "Hello **#{'x' * 30}**"
        xml = rendered_layout(card_text: long_text)
        document = REXML::Document.new(xml)
        bold = document.get_elements('//tspan[@font-weight="bold"]')

        expect(bold.map(&:text).join).to eq("x" * 30)
      end

      it "never truncates a card label with an ellipsis" do
        long_text = "Hello **#{'x' * 30}**"
        xml = rendered_layout(card_text: long_text)

        expect(xml).not_to include("...")
      end

      it "keeps a long later line in full instead of dropping it" do
        text = "Short\n#{'q' * 30}"
        xml = rendered_layout(card_text: text)
        tspans = REXML::Document.new(xml).get_elements("//tspan")

        expect(tspans.map(&:text).join.count("q")).to eq(30)
      end

      it "wraps a long card title onto several lines at word boundaries" do
        text = "Create Blog about the new diagram"
        xml = rendered_layout(card_text: text)
        lines = REXML::Document.new(xml).get_elements("//tspan").map(&:text)

        expect(lines).to eq(["Create Blog about the", "new diagram"])
      end

      # A markdown-styled run is the first attacker-facing markdown-to-XML
      # surface: label text an author writes ends up inside a `<tspan>`.
      # `<`, `&` and `"` must come out escaped, and REXML must still parse
      # the result, or a hostile label breaks or injects into the document.
      it "escapes XML-significant characters inside a styled run" do
        xml = rendered_layout(card_text: 'Plain **<b>&"x**')
        expect_escaped_styled_run(xml)
      end

      # Column header integration: markdown in the title renders the same
      # way as card text, and a header's pre-existing bold baseline
      # (`font_weight = "bold"` on the whole `Svg::Text`, set unconditionally
      # above) must survive on a PLAIN run once that baseline moves onto
      # per-run tspans. Mutation-check: drop the `base_font_weight` merge in
      # `build_markdown_tspans` (`run.bold || base_font_weight == "bold"`
      # becomes just `run.bold`). Watched red: the plain "Todo " run's
      # `<tspan>` loses `font-weight="bold"` entirely.
      it "renders bold in a column header, and keeps a plain header " \
         "run bold" do
        xml = rendered_layout(
          card_text: "plain", column_title: "Todo **urgent**",
        )
        expect_bold_header_runs(xml)
      end

      # Coverage gap closed: every example above checks tspan CONTENT
      # (`.text`/`include`), never that the positioning and styling
      # ATTRIBUTES that make a hard break or an italic run visually correct
      # actually reach the output XML. A mutation nil-ing every tspan's `x`
      # (or `font_style`) left the suite green before this example existed.
      #
      # Mutation-check: change `build_markdown_tspans` to `t.x = x` -> `t.x
      # = 0`. Watched red with the presence-only `not_to be_nil` in place
      # (proving that assertion alone caught nothing); asserting the actual
      # value (card x 10 + document padding 40 + card text inset 10) is what
      # catches it.
      it "carries x on the line-starting tspan after a hard break, and " \
         "font-style on an italic run" do
        line_xml = rendered_layout(card_text: "Line one\nLine two")
        italic_xml = rendered_layout(card_text: "Hello *urgent*")
        expect_line_and_italic_attributes(line_xml, italic_xml)
      end

      # Full-render coverage gap closed: every example above renders at
      # most ONE styling property per tspan through the actual XML. Nothing
      # exercised two properties landing on the SAME tspan through the real
      # `Renderer::Kanban#render` -> `to_xml` path — only `parse_lines`-level
      # `Run` structs were checked for that combination.
      #
      # Mutation-check: change `build_markdown_tspans`'s independent `if
      # run.bold ...` / `if run.italic ...` to an `if`/`elsif` pair.
      # Watched red: the single tspan carries `font-style="italic"` but
      # loses `font-weight="bold"`.
      it "renders ***both*** as one tspan carrying both bold and italic" do
        xml = rendered_layout(card_text: "***both***")
        run = first_xml_element(xml, '//tspan[text()="both"]')
        actual = [run.attributes["font-weight"], run.attributes["font-style"]]
        expect(actual).to eq(%w[bold italic])
      end

      # Mutation-check: move the `font_weight`/`font_style` assignments
      # inside the `if new_line` branch's guard so a line-starting run's
      # OWN styling is skipped (only the `x`/`dy` reset survives). Watched
      # red: the second tspan ("b", which is both line-starting AND bold)
      # loses `font-weight="bold"` while the first ("a") keeps it.
      it "keeps bold on both halves of a bold run split by a hard break" do
        xml = rendered_layout(card_text: "**a\nb**")
        expect(bold_split_state(xml)).to eq(["bold", "bold", true])
      end

      # The column header rect and its text's baseline must grow with a
      # multi-line title, not stay at a hardcoded single-line height — a
      # header that doesn't grow spills its lower tspans past the rect
      # onto the board background below it.
      it "grows the column header rect to fit a multi-line title, keeping " \
         "the tspans inside it" do
        xml = rendered_layout(
          card_text: "plain", column_title: "One\nTwo\nThree",
          header_height: 86
        )
        expect_three_line_header(xml)
      end

      # The spec above only pins the header rect GROWING to fit a
      # multi-line title — it doesn't catch the baseline itself overflowing
      # that (correctly grown) rect, since a 3-line title happens to leave
      # margin under the flat `y + header_height / 2 + 5` formula that a
      # 4-line title exhausts. `header_text_baseline` must center the whole
      # text BLOCK, not one fixed baseline, to keep every line inside.
      it "keeps every baseline of a 4-line column title inside its own " \
         "header rect" do
        xml = rendered_layout(
          card_text: "plain", column_title: "One\nTwo\nThree\nFour",
          header_height: 104
        )
        expect_four_line_header(xml)
      end

      # Round 3 Codex High: card metadata used to start at a fixed `y + 50`
      # regardless of how many lines the card's own label actually
      # rendered, so a multi-line label's later lines overlapped the
      # metadata rows drawn below it.
      #
      # Mutation-check: revert `render_card_metadata`'s `metadata_y` to
      # the hardcoded `y + 50`. Watched red: the metadata label's y stays
      # at the single-line offset, landing above the label's own last
      # rendered line instead of below it.
      it "starts card metadata below a multi-line label's actual " \
         "rendered height" do
        xml = rendered_layout(
          card_text: "A\nB\nC", card_height: 134, board_height: 200,
          metadata: { assigned: "Alice" }, has_metadata: true
        )
        expect_metadata_below_label(xml)
      end
    end
  end
end
