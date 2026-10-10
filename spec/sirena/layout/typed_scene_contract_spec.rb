# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Scene do
  let(:fixture_dir) { File.expand_path("../../fixtures/contract", __dir__) }

  Sirena::Notation::Mermaid::TYPES.each_key do |type|
    it "builds a bounded Scene for #{type}" do
      source = File.read(File.join(fixture_dir, "#{type}.mmd"))
      diagram = Sirena::Parser.for(type).parse(source)
      scene = Sirena::Layout.for(type).call(diagram)

      expect(scene).to be_a(described_class)
        .and have_attributes(
          width: be_between(Float::MIN, Float::MAX),
          height: be_between(Float::MIN, Float::MAX),
        )
    end
  end
end
