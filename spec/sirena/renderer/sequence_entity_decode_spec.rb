# frozen_string_literal: true

require "spec_helper"

# Drawn text measured with mmdc: references are decoded once, in the
# actor boxes and in message text alike.
module SequenceEntityRenderHelpers
  def drawn(body)
    Sirena::Engine.new.render("sequenceDiagram\n#{body}\n")
  end
end

RSpec.describe Sirena::Renderer::Sequence do
  include SequenceEntityRenderHelpers

  it "draws a decoded alias in the actor box" do
    svg = drawn("participant A as \"x#59;y\"\nA->>A: m")

    expect(svg).to include(">\"x;y\"</text>")
  end

  it "draws a decoded message once" do
    svg = drawn("A->>B: #35;59 #amp; #foo;")

    expect(svg).to include(">#59 &amp; &amp;foo;</text>")
  end

  it "draws a created participant's decoded alias" do
    svg = drawn("A->>B: x\ncreate participant C as c#59;d\nA->>C: y")

    expect(svg).to include(">c;d</text>")
  end
end
