# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  let(:directional_edge_source) do
    <<~MERMAID
      architecture-beta
      service left(server)[Left]
      service right(server)[Right]
      left:R -- L:right
    MERMAID
  end

  fixtures = %w[
    architecture_spec-5d965f8d
    architecture_spec-8afbb5a2
    architecture_spec-ae158359
  ]

  fixtures.each do |name|
    it "refuses #{name}'s legacy compact edge syntax" do
      path = File.expand_path("mermaid/architecture/#{name}.mmd", __dir__)

      expect { described_class.render(File.read(path)) }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  it "renders directional edges when positions use Mermaid's endpoint syntax" do
    expect(described_class.render(directional_edge_source))
      .to include('id="edge-left-right"')
  end
end
