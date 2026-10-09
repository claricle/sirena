# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

module ErLabelTextHelpers
  module_function

  def drawn_texts(source)
    doc = REXML::Document.new(Sirena::Engine.new.render(source))
    REXML::XPath.match(doc, "//*[local-name()='text']").map do |node|
      node.texts.map(&:value).join
    end
  end
end

RSpec.describe Sirena::Renderer::ErDiagram do
  # mermaid draws the type column before the name column
  # (spec/fixtures_mermaid/er/002_platform_yari2_er_1.svg).
  it "draws an attribute row as type then name" do
    texts = ErLabelTextHelpers.drawn_texts(
      "erDiagram\nCAR {\n  string registrationNumber\n  int age\n}\n",
    )

    expect(texts).to include("string registrationNumber", "int age")
  end
end
