# frozen_string_literal: true

require "digest"
require "rexml/document"
require "rexml/xpath"
require "spec_helper"
require "sirena/layout/treemap"
require "sirena/parser/treemap"
require "sirena/renderer/treemap"

RSpec.describe Sirena::Renderer::Treemap do
  subject(:document) { described_class.new(theme: theme).render(scene) }

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:diagram) { Sirena::Parser::Treemap.new.parse(source) }
  let(:scene) { Sirena::Layout::Treemap.new.call(diagram, theme: theme) }

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses label text for every text role" do
        expect(text_attribute("fill").uniq).to eq([theme.colors.label_text])
      end

      it "uses the named depth palette" do
        expect(cell_fills(scene.cells))
          .to eq(theme.colors.treemap_palette.first(2))
      end
    end
  end

  it "preserves the default SVG bytes" do
    expect(Digest::SHA256.hexdigest(document.to_xml))
      .to eq("a44d882ad575d7059b52a2aa7f8a27848ef9a7b256229b889835210ee94193a6")
  end

  context "with a scalar-empty partial theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new,
        typography: Sirena::Theme::Typography.new,
      )
    end

    it "leaves text paint unset and retains the typography fallback" do
      expect([text_attribute("fill").uniq, text_attribute("font-family").uniq])
        .to eq([[nil], ["Arial, sans-serif"]])
    end
  end

  it "keeps an explicit class fill ahead of the dark depth palette" do
    themed_diagram = Sirena::Parser::Treemap.new.parse(<<~MERMAID)
      treemap
      "Section"
        "Leaf": 5:::important
      classDef important fill:#f96,stroke:#333;
    MERMAID
    dark = Sirena::Theme::Registry.get(:dark)
    themed_scene = Sirena::Layout::Treemap.new.call(themed_diagram, theme: dark)

    expect(themed_scene.cells.first.children.first.fill).to eq("#f96")
  end

  def texts
    REXML::XPath.match(REXML::Document.new(document.to_xml), "//text")
  end

  def text_attribute(name)
    texts.map { |text| text.attributes[name] }
  end

  def cell_fills(cells)
    cells.flat_map { |cell| [cell.fill, *cell_fills(cell.children)] }
  end

  def source
    <<~MERMAID
      treemap
      title Theme roles
      "Section"
        "Leaf": 5
    MERMAID
  end
end
