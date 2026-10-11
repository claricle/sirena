# frozen_string_literal: true

require "digest"
require "spec_helper"
require "sirena/renderer/info"

RSpec.describe Sirena::Renderer::Info do
  subject(:svg) do
    described_class.new(theme: theme).render(show_info: false)
  end

  let(:theme) { Sirena::Theme::Registry.get(:default) }

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses the label text role" do
        expect(label.fill).to eq(theme.colors.label_text)
      end
    end
  end

  it "preserves the default SVG bytes" do
    expect(Digest::SHA256.hexdigest(svg.to_xml))
      .to eq("2d457ed0856c953396e48673674c8257f5f997404e864d5e4363d907f430d040")
  end

  context "with a scalar-empty partial theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new,
        typography: Sirena::Theme::Typography.new,
      )
    end

    it "leaves the fill unset and retains the typography fallback" do
      expect([label.fill, label.font_family]).to eq([nil, "Arial, sans-serif"])
    end
  end

  def label
    svg.children.grep(Sirena::Svg::Text).first
  end
end
