# frozen_string_literal: true

require "rexml/document"

# The contract every diagram type honors. `gaps` maps an area to the reason
# the type does not meet it yet; a gap runs as `pending`, so fixing the type
# turns the example red until the entry is deleted.
#   :empty_input   header-only source does not render
#   :theme_output  no built-in theme changes the SVG
RSpec.shared_examples "a diagram type" do |type, gaps = {}|
  let(:fixture) do
    File.read(File.join(__dir__, "..", "fixtures", "contract", "#{type}.mmd"))
  end
  let(:model) do
    Sirena::Notation::Mermaid.layer_class(Sirena::Diagram, type,
                                          Sirena::Error)
  end
  let(:diagram) { Sirena::Parser.for(type).parse(fixture) }
  let(:header_only) do
    header = fixture.lines.map(&:strip).find do |line|
      !line.empty? && !line.start_with?("%%")
    end
    "#{header}\n"
  end
  let(:themes) { %w[dark light high_contrast] }

  it "has a canonical fixture" do
    expect(File).to exist(File.join(__dir__, "..", "fixtures", "contract",
                                    "#{type}.mmd"))
  end

  it "resolves a parser inheriting Parser::Base" do
    expect(Sirena::Parser.for(type)).to be_a(Sirena::Parser::Base)
  end

  it "resolves a layout inheriting Layout::Base" do
    expect(Sirena::Layout.for(type)).to be_a(Sirena::Layout::Base)
  end

  it "resolves a renderer inheriting Renderer::Base" do
    expect(Sirena::Renderer.for(type)).to be_a(Sirena::Renderer::Base)
  end

  it "resolves a model inheriting Diagram::Base" do
    expect(model.ancestors).to include(Sirena::Diagram::Base)
  end

  it "parses the fixture into the convention-resolved model" do
    expect(diagram.class).to be(model)
  end

  it "returns diagram_type as the registered symbol" do
    expect(diagram.diagram_type).to eq(type)
  end

  # Call it and check the value: respond_to?(:valid?) is satisfied by the
  # inherited Diagram::Base#valid?, which raises NotImplementedError.
  it "answers valid? true for the fixture" do
    expect(diagram.valid?).to be(true)
  end

  it "renders the fixture to well-formed XML" do
    expect { REXML::Document.new(Sirena::Engine.new.render(fixture)) }
      .not_to raise_error
  end

  it "renders the fixture under every built-in theme" do
    svgs = themes.map { |t| Sirena::Engine.new(theme: t).render(fixture) }

    expect(svgs).to all(include("<svg"))
  end

  it "lets a built-in theme change the SVG" do
    pending(gaps[:theme_output]) if gaps[:theme_output]
    default = Sirena::Engine.new.render(fixture)
    svgs = themes.map { |t| Sirena::Engine.new(theme: t).render(fixture) }

    expect(svgs).to include(satisfy { |svg| svg != default })
  end

  it "renders header-only input without raising" do
    pending(gaps[:empty_input]) if gaps[:empty_input]

    expect { Sirena::Engine.new.render(header_only) }.not_to raise_error
  end
end
