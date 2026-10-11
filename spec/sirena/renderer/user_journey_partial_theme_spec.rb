# frozen_string_literal: true

require "spec_helper"
require "digest"
require "rexml/document"
require "rexml/xpath"

RSpec.describe Sirena::Renderer::UserJourney do
  let(:source) do
    <<~MERMAID
      journey
        title My Journey
        section Shopping
          Browse products: 5: Customer
    MERMAID
  end
  let(:partial_theme) do
    Sirena::Theme.new(
      name: "partial", colors: Sirena::Theme::ColorPalette.new,
    )
  end
  let(:partial_document) do
    diagram = Sirena::Parser::UserJourney.new.parse(source)
    scene = Sirena::Layout::UserJourney.new.call(diagram, theme: partial_theme)
    xml = described_class.new(theme: partial_theme).render(scene).to_xml
    REXML::Document.new(xml)
  end

  it "preserves the exact default render" do
    expect(Digest::SHA256.hexdigest(Sirena.render(source)))
      .to eq("3554dc5e2016a5b8db7b953452e56e02eab818d263a8126c96cc83b6e19b2b3f")
  end

  it "does not inject neutral paint into a scalar-empty partial theme" do
    expect(neutral_paints(partial_document).compact).to be_empty
  end

  it "retains categorical fills with a scalar-empty partial theme" do
    expect(categorical_fills(partial_document)).to eq(
      ["#191970", "#191970", "#fff", "#fff", "#FFF8DC", "#8FBC8F",
       "#8FBC8F"],
    )
  end

  def neutral_paints(document)
    selected_paints(document) + facial_paints(document)
  end

  def selected_paints(document)
    neutral_selectors.flat_map do |expression, attribute|
      xpath(document, expression).map do |element|
        element.attributes[attribute]
      end
    end
  end

  def neutral_selectors
    [
      ["//circle[starts-with(@class,'actor-')]", "stroke"],
      ["//rect[contains(@class,'section') or contains(@class,'task')]",
       "stroke"],
      ["//*[@class='task-line']", "stroke"],
      ["//circle[@class='face']", "stroke"],
      ["//line[not(@class)]", "stroke"],
      ["//path[not(@class)]", "fill"],
    ]
  end

  def facial_paints(document)
    facial = xpath(document, "//circle[not(@class)]") +
      xpath(document, "//*[@class='mouth']")
    attributes = %w[fill stroke]
    facial.flat_map do |element|
      attributes.map { |attribute| element.attributes[attribute] }
    end
  end

  def categorical_fills(document)
    elements = xpath(document, "//rect[contains(@class,'section') or " \
                               "contains(@class,'task')]")
    elements += xpath(document, "//text[contains(@class,'section') or " \
                                "@class='task']")
    elements += xpath(document, "//circle[@class='face']")
    elements += xpath(document, "//circle[starts-with(@class,'actor-')]")
    elements.map { |element| element.attributes["fill"] }
  end

  def xpath(document, expression)
    REXML::XPath.match(document, expression)
  end
end
