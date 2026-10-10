# frozen_string_literal: true

require "spec_helper"

module QuotedParenLabelHelpers
  def svg_text(source)
    engine.render(source).scan(%r{<text[^>]*>(.*?)</text>}m).flatten.join(" | ")
  end
end

RSpec.describe Sirena::Parser::Flowchart do
  include QuotedParenLabelHelpers

  let(:engine) { Sirena::Engine.new }

  describe "a paren inside a quoted round-node label" do
    [
      ["a plain quoted label", 'b("a (1)") --> c'],
      ["a markdown-string label", 'b("`a (1)`") --> c'],
    ].each do |name, line|
      it "draws #{name} whole and keeps the target node" do
        text = svg_text("flowchart LR\n#{line}")

        expect(text).to include("a (1)").and include("c")
      end
    end

    it "keeps the paren text of the corpus case that holds it" do
      source = File.read("spec/mermaid/unknown/018_platform_knsv_17.mmd")

      expect(svg_text(source)).to include("The dog in the hog.(1)")
    end

    %w[016_platform_knsv_15 017_platform_knsv_16].each do |name|
      it "renders corpus case #{name}" do
        source = File.read("spec/mermaid/unknown/#{name}.mmd")

        expect(svg_text(source))
          .to include("hog.(1)").and include("new strings")
      end
    end

    it "refuses a quote that never closes" do
      expect { engine.render("flowchart LR\nb(\"unterminated) --> c") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses a directive opened inside the quotes" do
      expect { engine.render("flowchart LR\nb(\"a\n%%{ bad }\nc\") --> d") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "does not let a quote inside a comment line end the label" do
      text = svg_text("flowchart LR\nb(\"a\n%% it\"s )\nc\") --> d")

      expect(text).to include("a").and include("c")
      expect(text).not_to include('%% it"s )')
    end

    it "leaves the other round labels of the diagram alone" do
      source = "flowchart LR\nb(\"a (1)\") --> c\nd(x y) --> e\n" \
               "f(p\n%% lone \"\nq) --> g"
      text = svg_text(source)

      expect(text).to include("a (1)").and include("x y").and include("g")
    end
  end
end
