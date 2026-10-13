# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Message do
  include_context "with an isolated notation registry"

  let(:sequence) { Sirena::Notation::PlantUML::Sequence }
  let(:source) do
    <<~PLANTUML
      @startuml
      !pragma teoz true
      autonumber
      A -> B: hello
      A -> B: ""hello""
      & B -> A: ""hello""
      @enduml
    PLANTUML
  end

  context "with numbered and parallel messages" do
    let(:rebuilt) do
      diagram = sequence::Parser.new.parse(source)
      sequence::IRReader.call(sequence::IRAdapter.call(diagram))
    end
    let(:messages) do
      rebuilt.messages.map do |message|
        [message.label, message.label_family, message.number, message.parallel?]
      end
    end
    let(:expected) do
      [["hello", nil, 1, false], ["hello", "monospace", 2, false],
       ["hello", "monospace", 3, true]]
    end

    it "preserves numbered and parallel font intent through typed IR" do
      expect(messages).to eq(expected)
    end
  end

  context "with end-to-end rendering" do
    let(:rendered_families) do
      Sirena::Notation.register(Sirena::Notation::PlantUML)
      doc = Nokogiri::XML(Sirena.render(source, notation: :plantuml))
      doc.remove_namespaces!
      doc.xpath('//g[starts-with(@id,"message-")]/text[text()="hello"]')
        .map { |text| text["font-family"] }
    end

    it "renders identical ordinary and quoted labels in their pinned faces" do
      expect(rendered_families).to eq(["sans-serif", "monospace", "monospace"])
    end
  end

  context "with classic messages" do
    let(:source) { super().sub("!pragma teoz true\n", "").sub("& B", "B") }
    let(:families) do
      parsed = sequence.parse(source)
      parsed.transform.new.call(parsed.diagram).arrows
        .map { |arrow| arrow.texts.first.family }
    end

    it "keeps the classic message typography supplied by its theme" do
      expect(families).to eq([nil, nil, nil])
    end
  end
end
