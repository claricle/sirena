# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::MemberRule do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  # The inked rules of class K when its body is `a`, the separator, `b`;
  # the compartment rule under the name is dropped; a separator leaves no
  # empty method compartment, so no rule closes the fields.
  def rules(separator)
    svg = Sirena.render("@startuml\nclass K {\n a\n #{separator}\n b\n}\n" \
                        "@enduml\n", notation: :plantuml)
    REXML::XPath.match(REXML::Document.new(svg), "//g[@id='class-K']/line")
      .drop(1).map do |line|
      [line.attributes["stroke-width"],
       line.attributes["stroke-dasharray"]]
    end
  end

  it "draws `..` dotted" do
    expect(rules("..")).to eq([["1.0", "1,2"]])
  end

  it "draws `==` as two solid lines" do
    expect(rules("==")).to eq([["1.0", nil], ["1.0", nil]])
  end

  it "draws `__` a hairline" do
    expect(rules("__")).to eq([["0.5", nil]])
  end

  it "draws `--` solid" do
    expect(rules("--")).to eq([["1.0", nil]])
  end

  it "breaks a titled rule around its title, in the same style" do
    expect(rules(".. t ..")).to eq([["1.0", "1,2"], ["1.0", "1,2"]])
  end

  it "draws the two lines of `==` two pixels apart" do
    svg = Sirena.render("@startuml\nclass K {\n a\n ==\n b\n}\n@enduml\n",
                        notation: :plantuml)
    ys = REXML::XPath.match(REXML::Document.new(svg), "//g[@id='class-K']/line")
      .drop(1).map { |line| line.attributes["y1"].to_f }

    expect(ys.last - ys.first).to eq(2.0)
  end
end
