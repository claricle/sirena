# frozen_string_literal: true

require "spec_helper"
require "digest"
require "rexml/document"
require "rexml/xpath"

RSpec.describe Sirena::Renderer::Sequence do
  let(:source) do
    <<~MERMAID
      sequenceDiagram
      box Team
      participant A
      end
      alt Ok
      A->>A: x
      else Retry
      A->>A: y
      end
      rect
      A->>A: z
      end
    MERMAID
  end

  it "preserves the exact default render" do
    digest = Digest::SHA256.hexdigest(Sirena::Engine.new.render(source))

    expect(digest)
      .to eq("188e0cec8556f903340f4a895bd25e917bec2cc30e2ddce3244a32f2236e50fe")
  end

  it "uses semantic roles for boxes and control frames" do
    document = render_document(:dark)

    expect(frame_paints(document)).to eq(
      ["#858585", "#d4d4d4", "#858585", "#3e3e42", "#858585",
       "#d4d4d4", "#d4d4d4", "#d4d4d4", "#858585", "#404040"],
    )
  end

  it "does not invent frame paint for a scalar-empty partial theme" do
    theme = Sirena::Theme.new(name: "partial")

    expect(frame_paints(render_document(theme)).compact).to be_empty
  end

  it "retains an explicit rect colour over the theme role" do
    colored = source.sub("rect\n", "rect rgb(200,200,255)\n")

    expect(rect_fill(render_document(:dark, colored)))
      .to eq("rgb(200,200,255)")
  end

  def render_document(theme, input = source)
    REXML::Document.new(Sirena::Engine.new(theme: theme).render(input))
  end

  def rect_fill(document)
    element(document, "//*[@id='frame-1']/rect").attributes["fill"]
  end

  def frame_paints(document)
    box = "//*[@id='box-0']"
    alt = "//*[@id='frame-0']"
    rect = "//*[@id='frame-1']"
    [attribute(document, "#{box}/rect", "stroke"),
     attribute(document, "#{box}/text", "fill"),
     attribute(document, "#{alt}/rect", "stroke"),
     attribute(document, "#{alt}/polygon", "fill"),
     attribute(document, "#{alt}/polygon", "stroke"),
     *elements(document, "#{alt}/text").map { |item| item.attributes["fill"] },
     attribute(document, "#{alt}/line", "stroke"),
     attribute(document, "#{rect}/rect", "fill")]
  end

  def attribute(document, expression, name)
    element(document, expression).attributes[name]
  end

  def element(document, expression)
    REXML::XPath.first(document, expression)
  end

  def elements(document, expression)
    REXML::XPath.match(document, expression)
  end
end
