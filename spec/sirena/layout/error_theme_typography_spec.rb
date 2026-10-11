# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "rexml/xpath"

RSpec.describe Sirena::Layout::Error do
  subject(:message_sizes) do
    themes.to_h { |name, theme| [name, message_size(theme)] }
  end

  let(:themes) do
    {
      default: :default, light: :light, dark: :dark,
      high_contrast: :high_contrast,
      partial: Sirena::Theme.new(name: "partial")
    }
  end

  it "uses the large theme role for the rendered error message" do
    expect(message_sizes).to eq(
      default: 16.0, light: 16.0, dark: 16.0,
      high_contrast: 18.0, partial: 16.0
    )
  end

  def message_size(theme)
    document = REXML::Document.new(Sirena.render("error\n", theme: theme))
    label = REXML::XPath.first(document, "//*[local-name()='text']")
    label.attributes["font-size"].to_f
  end
end
