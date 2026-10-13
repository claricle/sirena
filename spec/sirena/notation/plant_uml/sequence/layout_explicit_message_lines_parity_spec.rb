# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:fixture) do
    File.expand_path("../../../../plantuml/sequence/" \
                     "resources.vega.asciiverse.basic_002--184d55bcfb9c.puml",
                     __dir__)
  end
  let(:scene) do
    parsed = Sirena::Notation::PlantUML::Sequence.parse(File.read(fixture))
    parsed.transform.new.call(parsed.diagram)
  end

  it "renders basic_002 explicit message lines separately" do
    labels = scene.arrows.last(2).map do |arrow|
      arrow.texts.map(&:content)
    end

    expected = [
      ["this is an", "example of long", "message"],
      ["And this", "is an other on", "very long too"],
    ]

    expect(labels).to eq(expected)
  end

  it "stacks basic_002 lines at the pinned message leading" do
    ys = scene.arrows[2].texts.map(&:y)
    gaps = ys.each_cons(2).map { |first, second| second - first }

    expect(gaps).to all(be_within(0.0001).of(15.3088))
  end

  it "interprets quote delimiters after resolving escaped line breaks" do
    examples = [
      [1, "one", ['""one', 'two""']],
      [2, "one", ['one\\ntwo']],
      [1, "path%<slashes>sdir one" % { slashes: "\\" * 2 },
       ['""path\\dir one', 'two""']],
      [2, "path%<slashes>sdir one" % { slashes: "\\" * 2 },
       ['path\\dir one\\ntwo']],
    ]
    actual = examples.map do |slashes, prefix, _|
      label = '""%<prefix>s%<slashes>sntwo""' % { prefix: prefix,
                                                  slashes: "\\" * slashes }
      parsed = Sirena::Notation::PlantUML::Sequence.parse(
        "@startuml\nA -> B : #{label}\n@enduml\n",
      )
      parsed.transform.new.call(parsed.diagram).arrows.first.texts.map(&:content)
    end

    expect(actual).to eq(examples.map(&:last))
  end
end
