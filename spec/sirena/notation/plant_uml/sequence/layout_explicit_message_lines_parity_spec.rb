# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  context "with basic_002 explicit message lines" do
    let(:fixture) do
      File.expand_path("../../../../plantuml/sequence/" \
                       "resources.vega.asciiverse.basic_002--184d55bcfb9c.puml",
                       __dir__)
    end
    let(:scene) do
      parsed = Sirena::Notation::PlantUML::Sequence.parse(File.read(fixture))
      parsed.transform.new.call(parsed.diagram)
    end
    let(:labels) do
      scene.arrows.last(2).map { |arrow| arrow.texts.map(&:content) }
    end
    let(:expected_labels) do
      [
        ["this is an", "example of long", "message"],
        ["And this", "is an other on", "very long too"],
      ]
    end

    it "renders basic_002 explicit message lines separately" do
      expect(labels).to eq(expected_labels)
    end

    it "stacks basic_002 lines at the pinned message leading" do
      ys = scene.arrows[2].texts.map(&:y)
      gaps = ys.each_cons(2).map { |first, second| second - first }

      expect(gaps).to all(be_within(0.0001).of(15.3088))
    end
  end

  context "with escaped quoted message labels" do
    let(:quoted_examples) do
      [
        [1, "one", ['""one', 'two""']],
        [2, "one", ['one\\ntwo']],
        [1, "path%<slashes>sdir one" % { slashes: "\\" * 2 },
         ['""path\\dir one', 'two""']],
        [2, "path%<slashes>sdir one" % { slashes: "\\" * 2 },
         ['path\\dir one\\ntwo']],
      ]
    end
    let(:quoted_labels) do
      quoted_examples.map do |slashes, prefix, _|
        label = '""%<prefix>s%<slashes>sntwo""' % { prefix: prefix,
                                                    slashes: "\\" * slashes }
        parsed = Sirena::Notation::PlantUML::Sequence.parse(
          "@startuml\nA -> B : #{label}\n@enduml\n",
        )
        quoted_scene = parsed.transform.new.call(parsed.diagram)
        quoted_scene.arrows.first.texts.map(&:content)
      end
    end

    it "interprets quote delimiters after resolving escaped line breaks" do
      expect(quoted_labels).to eq(quoted_examples.map(&:last))
    end
  end
end
