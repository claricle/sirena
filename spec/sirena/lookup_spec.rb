# frozen_string_literal: true

require "spec_helper"

# Parser.for, Layout.for and Renderer.for: three cases each, and every layer
# raises its own error class when a known type's class does not resolve.
RSpec.describe Sirena::Notation::Mermaid, "per-layer lookups" do
  let(:row) { Sirena::Notation::Mermaid::TYPES.fetch(:pie) }

  {
    Sirena::Parser => [Sirena::Parser::Pie, Sirena::Parser::ParseError],
    Sirena::Layout => [Sirena::Layout::Pie, Sirena::Layout::LayoutError],
    Sirena::Renderer => [Sirena::Renderer::Pie, Sirena::Renderer::RenderError],
  }.each do |layer, (pie_class, layer_error)|
    describe "#{layer}.for" do
      it "raises DiagramTypeError for a type not in TYPES" do
        expect { layer.for(:no_such_type) }
          .to raise_error(Sirena::Engine::DiagramTypeError)
      end

      it "returns an instance of the convention-resolved class" do
        expect(layer.for(:pie).class).to be(pie_class)
      end

      it "returns a different object on every call" do
        expect(layer.for(:pie).object_id).not_to eq(layer.for(:pie).object_id)
      end

      it "raises #{layer_error} for a known type whose class is missing" do
        stub_const(
          "Sirena::Notation::Mermaid::TYPES",
          Sirena::Notation::Mermaid::TYPES.merge(
            pie: row.merge(name: "NoSuchClass"),
          ),
        )

        expect { layer.for(:pie) }.to raise_error(layer_error, /NoSuchClass/)
      end
    end
  end

  it "gives the renderer the theme" do
    theme = Sirena::Theme::Registry.get(:dark)

    expect(Sirena::Renderer.for(:pie, theme: theme).theme).to be(theme)
  end

  it "resolves :xychart to XyChart through its row's name" do
    expect(Sirena::Layout.for(:xychart)).to be_a(Sirena::Layout::XyChart)
  end

  # A misnamed layout must fail the render, not draw an unlaid-out diagram.
  it "fails a render whose layout constant does not resolve" do
    stub_const(
      "Sirena::Notation::Mermaid::TYPES",
      Sirena::Notation::Mermaid::TYPES.merge(
        pie: row.merge(name: "NoSuchClass"),
      ),
    )

    expect { Sirena.render("pie\n\"a\": 1") }
      .to raise_error(Sirena::Parser::ParseError, /NoSuchClass/)
  end
end
