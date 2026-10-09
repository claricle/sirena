# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement do
  def texts_of(svg)
    svg.scan(%r{<text[^>]*>([^<]*)</text>}).flatten
  end

  let(:svg) { Sirena::Engine.new.render(source) }
  let(:texts) { texts_of(svg) }

  context "with a bare requirement and a typeless element" do
    let(:source) do
      <<~MERMAID
        requirementDiagram
          requirement bare {
          }
          element lone {
          }
          lone - satisfies -> bare
      MERMAID
    end

    it "prints only the header type and names, no property lines",
       :aggregate_failures do
      expect(texts).to include("Requirement", "bare", "lone")
      expect(texts.grep(/\A(ID|Risk|Verify|Type):/)).to be_empty
    end

    it "labels the relationship with its type" do
      expect(texts).to include("satisfies")
    end
  end

  context "with every property and a long text" do
    let(:source) do
      <<~MERMAID
        requirementDiagram
          requirement full {
            id: 1
            text: this is a rather long requirement text that must wrap across several lines of the box
            risk: high
            verifymethod: test
          }
          element typed {
            type: simulation
          }
          typed - verifies -> full
      MERMAID
    end

    let(:body) do
      chrome = /\A(ID|Risk|Verify|Type):|\A(Requirement|full|typed|verifies)\z/
      texts.grep_v(chrome)
    end
    let(:full_text) do
      "this is a rather long requirement text that must wrap " \
        "across several lines of the box"
    end

    it "wraps the text onto several lines without losing words",
       :aggregate_failures do
      expect(body.size).to be > 1
      expect(body.join(" ")).to eq(full_text)
    end

    it "prints capitalised risk and verify lines and the element type" do
      expect(texts).to include("ID: 1", "Risk: High", "Verify: Test",
                               "Type: simulation")
    end
  end

  context "with a layout that has no sections" do
    it "renders an empty document and wraps empty text to no lines",
       :aggregate_failures do
      renderer = described_class.new(theme: Sirena::Theme::Registry.get(:default))
      expect(renderer.render({}).to_xml).not_to include("<text")
      expect(renderer.send(:wrap_text, "", 100, 12)).to eq([])
    end
  end
end
