# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::Info do
  let(:diagram) { Sirena::Diagram::Info.new }
  let(:default_theme) { Sirena::Theme::Registry.get(:default) }
  let(:theme) { default_theme }
  let(:scene) { described_class.new.call(diagram, theme: theme) }
  let(:svg) do
    Sirena::Renderer::Info.new(theme: theme).render(scene).to_xml
  end

  it "preserves the default title size and SVG bytes" do
    digest = "2d457ed0856c953396e48673674c8257f" \
             "5f997404e864d5e4363d907f430d040"
    expect([scene.label.font_size, Digest::SHA256.hexdigest(svg)])
      .to eq([32.0, digest])
  end

  context "with the high-contrast theme" do
    let(:theme) { Sirena::Theme::Registry.get(:high_contrast) }

    it "scales the version title from the title typography role" do
      expect(scene.label.font_size).to eq(38.4)
    end
  end

  context "with a scalar-empty typography" do
    let(:theme) do
      Sirena::Theme.new(typography: Sirena::Theme::Typography.new)
    end

    it "uses the registered default title size" do
      expect(scene.label.font_size).to eq(32.0)
    end
  end
end
