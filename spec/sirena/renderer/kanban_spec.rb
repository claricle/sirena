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
              card_count: 1
            },
            {
              id: 'done',
              title: 'Done',
              x: 260,
              y: 0,
              width: 200,
              height: 150,
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
      def layout_with(card_text:, column_title: 'Todo')
        {
          columns: [
            {
              id: 'todo',
              title: column_title,
              x: 0,
              y: 0,
              width: 200,
              height: 150,
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
    end
  end
end