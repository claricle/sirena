# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Layout::UserJourney do
  let(:source) do
    <<~MERMAID
      journey
        title Theme journey
        section First
          Begin: 5: Alpha
    MERMAID
  end
  let(:default_sizes) do
    {
      "Alpha" => 16.0, "First" => 14.0, "Begin" => 14.0,
      "Theme journey" => 32.0
    }
  end
  let(:expected_themes) do
    {
      default: default_sizes,
      light: default_sizes,
      dark: default_sizes,
      high_contrast: default_sizes.merge(
        "Alpha" => 18.0, "First" => 16.0, "Begin" => 16.0,
      ),
      { colors: { primary: "#123456" } } => default_sizes,
      { typography: {
        font_size_large: 21, font_size_normal: 17
      } } => default_sizes.merge(
        "Alpha" => 21.0, "First" => 17.0, "Begin" => 17.0,
      ),
    }
  end

  def text_sizes(theme)
    document = REXML::Document.new(Sirena.render(source, theme: theme))

    REXML::XPath.match(document, "//*[local-name()='text']").to_h do |text|
      [text.text.to_s, text.attributes["font-size"].to_f]
    end
  end

  it "uses semantic typography roles without changing established themes" do
    actual = expected_themes.to_h { |theme, _| [theme, text_sizes(theme)] }

    expect(actual).to eq(expected_themes)
  end
end
