# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'

RSpec.describe Sirena::Renderer::Kanban do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe '#render' do
    context 'with a simple kanban board' do
      let(:layout) do
        {
          columns: [
            {
              id: 'todo',
              title: 'Todo',
              x: 0,
              y: 0,
              width: 200,
              height: 150,
              header_height: 50,
              card_count: 1
            }
          ],
          cards: [
            {
              id: 'docs',
              text: 'Create Documentation',
              column_id: 'todo',
              x: 10,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false
            }
          ],
          width: 200,
          height: 150
        }
      end

      it 'renders an SVG document' do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end

      it 'includes column elements' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('rect')
        expect(xml).to include('Todo')
      end

      it 'includes card elements' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Create Documentation')
      end
    end

    context 'with multiple columns' do
      let(:layout) do
        {
          columns: [
            {
              id: 'todo',
              title: 'Todo',
              x: 0,
              y: 0,
              width: 200,
              height: 150,
              header_height: 50,
              card_count: 1
            },
            {
              id: 'done',
              title: 'Done',
              x: 260,
              y: 0,
              width: 200,
              height: 150,
              header_height: 50,
              card_count: 1
            }
          ],
          cards: [
            {
              id: 'docs',
              text: 'Create Documentation',
              column_id: 'todo',
              x: 10,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false
            },
            {
              id: 'release',
              text: 'Release v1.0',
              column_id: 'done',
              x: 270,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false
            }
          ],
          width: 460,
          height: 150
        }
      end

      it 'renders all columns' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Todo')
        expect(xml).to include('Done')
      end

      it 'renders all cards' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Create Documentation')
        expect(xml).to include('Release v1.0')
      end
    end

    context 'with card metadata' do
      let(:layout) do
        {
          columns: [
            {
              id: 'todo',
              title: 'Todo',
              x: 0,
              y: 0,
              width: 200,
              height: 180,
              header_height: 50,
              card_count: 1
            }
          ],
          cards: [
            {
              id: 'docs',
              text: 'Create Documentation',
              column_id: 'todo',
              x: 10,
              y: 60,
              width: 180,
              height: 110,
              metadata: {
                priority: 'High',
                ticket: 'MC-1001'
              },
              has_metadata: true
            }
          ],
          width: 200,
          height: 180
        }
      end

      it 'renders metadata' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Priority')
        expect(xml).to include('High')
        expect(xml).to include('Ticket')
        expect(xml).to include('MC-1001')
      end
    end

    context 'with empty board' do
      let(:layout) do
        {
          columns: [],
          cards: [],
          width: 0,
          height: 0
        }
      end

      it 'renders without errors' do
        expect { renderer.render(layout) }.not_to raise_error
      end
    end

    context 'with markdown in card and column labels' do
      def layout_with(card_text:, column_title: 'Todo', header_height: 50)
        {
          columns: [
            {
              id: 'todo',
              title: column_title,
              x: 0,
              y: 0,
              width: 200,
              height: 150,
              header_height: header_height,
              card_count: 1
            }
          ],
          cards: [
            {
              id: 'card',
              text: card_text,
              column_id: 'todo',
              x: 10,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false
            }
          ],
          width: 200,
          height: 150
        }
      end

      # Regression guard for the reported bug: mermaid renders `**urgent**`
      # as bold, sirena printed it literally. Mutation-check: revert
      # `render_card_text` to build `Svg::Text` with `t.content =
      # truncate_text(card[:text], 25)` directly (the pre-feature code).
      # Watched red: the assertions below fail — the literal `**` reappears
      # in the XML and no `<tspan font-weight="bold">` exists.
      it 'renders a bold card run as a <tspan font-weight="bold">, with no literal markers' do
        xml = renderer.render(layout_with(card_text: 'Hello **urgent**')).to_xml

        expect(xml).to match(%r{<tspan[^>]*font-weight="bold"[^>]*>urgent</tspan>})
        expect(xml).to include('<tspan>Hello </tspan>')
        expect(xml).not_to include('**')
      end

      # Truncation composes with markdown: a card text longer than 25
      # rendered characters, where the cut falls INSIDE a bold run, still
      # truncates on run boundaries rather than the raw markup string. A
      # naive `text[0...22]` on "Hello **xxxx...xxx**" would cut through
      # the closing `**`, leaving a stray asterisk and an unclosed style;
      # `truncate_runs` cuts the already-parsed run instead, so the marker
      # characters were never in the string being sliced.
      #
      # Mutation-check: change `render_card_text` to compute
      # `truncate_text(card[:text], 25)` on the raw string and pass that
      # (re-parsed) to `assign_markdown_text` instead of truncating the
      # parsed runs. Watched red: a lone `*` appears in the output and the
      # bold run never closes cleanly at "...".
      it 'truncates a markdown card label on run boundaries, never mid-marker' do
        long_text = "Hello **#{'x' * 30}**"
        xml = renderer.render(layout_with(card_text: long_text)).to_xml

        expect(xml).not_to match(/(?<!\*)\*(?!\*)/) # no lone, unpaired '*'
        expect(xml).to match(%r{<tspan[^>]*font-weight="bold"[^>]*>x{16}\.\.\.</tspan>})
        expect { REXML::Document.new(xml) }.not_to raise_error
      end

      # A hard line break composes with truncation the same way: when the
      # SECOND line alone overflows the remaining budget, it is dropped
      # whole, never cut partway through. Only the first line ever gets a
      # partial "..." cut.
      it 'drops a later line whole on overflow, never truncating it mid-line' do
        long_text = "Short\n#{'q' * 30}"
        xml = renderer.render(layout_with(card_text: long_text)).to_xml

        expect(xml).to include('Short')
        expect(xml).not_to include('q')
        expect(xml).not_to include('...')
        expect { REXML::Document.new(xml) }.not_to raise_error
      end

      # A markdown-styled run is the first attacker-facing markdown-to-XML
      # surface: label text an author writes ends up inside a `<tspan>`.
      # `<`, `&` and `"` must come out escaped, and REXML must still parse
      # the result, or a hostile label breaks or injects into the document.
      it 'escapes XML-significant characters inside a styled run' do
        xml = renderer.render(layout_with(card_text: 'Plain **<b>&"x**')).to_xml

        expect(xml).to include('<tspan font-weight="bold">&lt;b&gt;&amp;"x</tspan>')
        expect(xml).not_to include('<b>')

        parsed = REXML::Document.new(xml)
        bold_tspan = REXML::XPath.first(parsed, '//tspan[@font-weight="bold"]')
        expect(bold_tspan.text).to eq('<b>&"x')
      end

      # Column header integration: markdown in the title renders the same
      # way as card text, and a header's pre-existing bold baseline
      # (`font_weight = "bold"` on the whole `Svg::Text`, set unconditionally
      # above) must survive on a PLAIN run once that baseline moves onto
      # per-run tspans. Mutation-check: drop the `base_font_weight` merge in
      # `build_markdown_tspans` (`run.bold || base_font_weight == "bold"`
      # becomes just `run.bold`). Watched red: the plain "Todo " run's
      # `<tspan>` loses `font-weight="bold"` entirely.
      it 'renders bold in a column header, and keeps a plain header run bold' do
        xml = renderer.render(layout_with(card_text: 'plain', column_title: 'Todo **urgent**')).to_xml

        expect(xml).to match(%r{<tspan[^>]*font-weight="bold"[^>]*>urgent</tspan>})
        expect(xml).to match(%r{<tspan[^>]*font-weight="bold"[^>]*>Todo </tspan>})
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
      it 'carries x on the line-starting tspan after a hard break, and font-style on an italic run' do
        xml = renderer.render(layout_with(card_text: "Line one\nLine two")).to_xml
        parsed = REXML::Document.new(xml)
        second_line = REXML::XPath.first(parsed, '//tspan[text()="Line two"]')

        expect(second_line.attributes['x']).to eq('60.0')
        expect(second_line.attributes['dy']).to eq('1.2em')

        italic_xml = renderer.render(layout_with(card_text: 'Hello *urgent*')).to_xml
        italic_run = REXML::XPath.first(REXML::Document.new(italic_xml), '//tspan[text()="urgent"]')

        expect(italic_run.attributes['font-style']).to eq('italic')
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
      it 'renders ***both*** as one tspan carrying both bold and italic' do
        xml = renderer.render(layout_with(card_text: '***both***')).to_xml
        run = REXML::XPath.first(REXML::Document.new(xml), '//tspan[text()="both"]')

        expect(run.attributes['font-weight']).to eq('bold')
        expect(run.attributes['font-style']).to eq('italic')
      end

      # Mutation-check: move the `font_weight`/`font_style` assignments
      # inside the `if new_line` branch's guard so a line-starting run's
      # OWN styling is skipped (only the `x`/`dy` reset survives). Watched
      # red: the second tspan ("b", which is both line-starting AND bold)
      # loses `font-weight="bold"` while the first ("a") keeps it.
      it 'keeps bold on both halves of a bold run split by a hard break' do
        xml = renderer.render(layout_with(card_text: "**a\nb**")).to_xml
        parsed = REXML::Document.new(xml)
        first_half = REXML::XPath.first(parsed, '//tspan[text()="a"]')
        second_half = REXML::XPath.first(parsed, '//tspan[text()="b"]')

        expect(first_half.attributes['font-weight']).to eq('bold')
        expect(second_half.attributes['font-weight']).to eq('bold')
        expect(second_half.attributes['dy']).to eq('1.2em')
      end

      # Round 3 Codex High: the column header background rect and the
      # header text's own baseline both used to assume a single-line
      # title — `render_column_header`'s `header_height` was a hardcoded
      # local `50`, independent of anything Transform computed for a
      # title with embedded hard breaks. A 3-line title grew nothing, so
      # its lower tspans spilled past the header rect onto the board
      # background below it.
      #
      # Mutation-check: revert `header_height` to the hardcoded local
      # `50`. Watched red: the header rect's height assertion fails
      # (stays "50.0"), and the last line's computed baseline lands past
      # the (unchanged) header bottom instead of inside it.
      it 'grows the column header rect to fit a multi-line title, keeping the tspans inside it' do
        layout = layout_with(card_text: 'plain', column_title: "One\nTwo\nThree", header_height: 86)
        xml = renderer.render(layout).to_xml
        parsed = REXML::Document.new(xml)

        header_rect = REXML::XPath.first(parsed, "//rect[@height='86.0']")
        header_text = REXML::XPath.first(parsed, '//text[tspan]')
        tspan_count = header_text.elements.to_a('tspan').size

        expect(header_rect).not_to be_nil
        expect(tspan_count).to eq(3)

        font_size = header_text.attributes['font-size'].to_f
        first_baseline = header_text.attributes['y'].to_f
        last_baseline = first_baseline + ((tspan_count - 1) * font_size * 1.2)
        header_bottom = header_rect.attributes['y'].to_f + header_rect.attributes['height'].to_f

        expect(last_baseline).to be < header_bottom
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
      it "starts card metadata below a multi-line label's actual rendered height" do
        layout = {
          columns: [
            { id: 'todo', title: 'Todo', x: 0, y: 0, width: 200, height: 200, header_height: 50, card_count: 1 }
          ],
          cards: [
            {
              id: 'card',
              text: "A\nB\nC",
              column_id: 'todo',
              x: 10,
              y: 60,
              width: 180,
              height: 134,
              metadata: { assigned: 'Alice' },
              has_metadata: true
            }
          ],
          width: 200,
          height: 200
        }

        xml = renderer.render(layout).to_xml
        parsed = REXML::Document.new(xml)

        label_text = REXML::XPath.first(parsed, '//text[tspan]')
        label_tspan_count = label_text.elements.to_a('tspan').size
        metadata_label = REXML::XPath.first(parsed, "//text[.='Assigned:']")

        font_size = label_text.attributes['font-size'].to_f
        first_baseline = label_text.attributes['y'].to_f
        last_label_baseline = first_baseline + ((label_tspan_count - 1) * font_size * 1.2)

        expect(label_tspan_count).to eq(3)
        expect(metadata_label.attributes['y'].to_f).to be > last_label_baseline
      end
    end
  end
end