# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart do
  it "stringifies mapping-valued metadata keys like JavaScript" do
    sources = [
      <<~MERMAID,
        graph TD
        A@{
        ?
          a: b
        : ignored
        shape: hexagon
        }
      MERMAID
      <<~MERMAID,
        graph TD
        A@{
        ?
          - a: b
        : ignored
        shape: rounded
        }
      MERMAID
    ]

    shapes = sources.map do |source|
      described_class.new.parse(source).nodes.fetch(0).shape
    end

    expect(shapes).to eq(%w[hexagon rounded])
  end
end
