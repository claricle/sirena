# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Svg::Text do
  # `content` must stay readable through `Array(content)` regardless of
  # lutaml-model version -- see `Svg::Text#body` (lib/sirena/svg/text.rb) for
  # why. This property is independent of the deleted `xml do` mapping: it
  # holds for a renderer-constructed instance, which is the only way a Text
  # is built now that `from_xml` raises (see svg_no_xml_mapping_spec.rb).
  #
  # Diagnostic, not a mutation-prover: `Array('plain string').join` equals
  # 'plain string' whether or not `collection: true` is on the attribute, so
  # dropping it does not turn this example red. Keep it anyway -- it pins the
  # cross-version read-back contract `#body` relies on, which is exactly what
  # broke lutaml-model 0.7 -> 0.8 (see the file's git history).
  describe "#content" do
    it "reads back a scalar assignment as something Array() flattens to " \
       "that scalar, on any lutaml-model 0.8.x" do
      text = described_class.new
      text.content = "plain string"

      expect(Array(text.content).join).to eq("plain string")
    end
  end

  describe "text-decoration, textLength and lengthAdjust" do
    let(:plain) do
      described_class.new.tap do |t|
        t.x = "1"
        t.y = "2"
        t.content = "ab"
      end
    end
    let(:styled) do
      plain.dup.tap do |t|
        t.text_decoration = "underline line-through"
        t.text_length = 12.5
        t.length_adjust = "spacing"
      end
    end

    it "writes all three under their SVG names" do
      expect(styled.to_xml).to include(
        'text-decoration="underline line-through"',
        'textLength="12.5"', 'lengthAdjust="spacing"'
      )
    end

    it "writes none of them when unset" do
      expect(plain.to_xml)
        .not_to match(/text-decoration|textLength|lengthAdjust/)
    end
  end
end
