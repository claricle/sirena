# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::C4 do
  let(:source) { File.read("examples/c4/02-container-diagram.mmd") }
  let(:high_contrast) { Sirena::Theme::Registry.get(:high_contrast) }
  let(:custom_theme) do
    Sirena::Theme.new(
      name: "custom",
      colors: high_contrast.colors,
      typography: Sirena::Theme::Typography.new(font_family: "Example Sans"),
    )
  end

  def font_families(theme)
    document = REXML::Document.new(Sirena.render(source, theme: theme))

    REXML::XPath.match(document, "//*[local-name()='text']")
      .map { |text| text.attributes["font-family"] }.uniq
  end

  it "preserves the exact registered-default SVG" do
    expect(Digest::SHA256.hexdigest(Sirena.render(source)))
      .to eq("ae42d7be69d02d8fa8133d587e3cd59d1f477dd64b680234518056be1611fdf3")
  end

  it "renders non-default built-in and custom theme families" do
    actual = [font_families(:high_contrast), font_families(custom_theme)]
    expected = [[high_contrast.typography.font_family], ["Example Sans"]]

    expect(actual).to eq(expected)
  end

  it "retains the legacy family for scalar-empty typography" do
    theme = Sirena::Theme.new(
      name: "empty", typography: Sirena::Theme::Typography.new,
    )

    expect(font_families(theme)).to eq(["Arial, sans-serif"])
  end
end
