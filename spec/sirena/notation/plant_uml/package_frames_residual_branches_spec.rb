# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::PackageFrames do
  let(:source) do
    [
      "@startuml",
      "+package Icons {",
      "class A",
      "}",
      "package Plain <<Frame>> {",
      "class B",
      "}",
      "@enduml",
      "",
    ].join("\n")
  end
  let(:frames) do
    parsed = Sirena::Notation::PlantUML.parse(source)
    Sirena::Notation::PlantUML::Layout.new.call(parsed.diagram).frames
  end
  let(:attributes) do
    frames.map do |frame|
      [frame.id, frame.icon, frame.tab_width, frame.texts.first.x - frame.x]
    end
  end
  let(:expected_attributes) do
    [
      ["package-Icons", true, 76.0, 24.0],
      ["package-Plain", false, nil, 10.0],
    ]
  end

  it "distinguishes icon folders from plain package frames" do
    expect(attributes).to eq(expected_attributes)
  end
end
