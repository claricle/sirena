# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::SequenceWrap do
  body = "sequenceDiagram\nA->>B: x"

  {
    "the bare directive" => "#{body}\n%%{wrap}%%",
    "the bare directive before the diagram" => "%%{wrap}%%\n#{body}",
    "top-level init wrap" => %(%%{init: {"wrap": true}}%%\n#{body}),
    "sequence init wrap" =>
      "%%{init: {'sequence': {'wrap': true}}}%%\n#{body}",
  }.each do |name, source|
    it "is on for #{name}" do
      expect(described_class.on?(source)).to be(true)
    end
  end

  {
    "no directive" => body,
    "an init without wrap" => "%%{init: {'theme': 'dark'}}%%\n#{body}",
    "wrap set to false" => %(%%{init: {"wrap": false}}%%\n#{body}),
    "wrap in message text" => "sequenceDiagram\nA->>B: wrap: x",
  }.each do |name, source|
    it "is off for #{name}" do
      expect(described_class.on?(source)).to be(false)
    end
  end
end
