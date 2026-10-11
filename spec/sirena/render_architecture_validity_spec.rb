# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Architecture public-render validity" do
  fixtures = %w[
    architecture_spec-5d965f8d
    architecture_spec-8afbb5a2
    architecture_spec-ae158359
  ]

  fixtures.each do |name|
    it "refuses #{name}'s legacy compact edge syntax" do
      path = File.expand_path("../mermaid/architecture/#{name}.mmd", __dir__)

      expect { Sirena.render(File.read(path)) }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  it "renders directional edges when positions use Mermaid's endpoint syntax" do
    source = <<~MERMAID
      architecture-beta
      service left(server)[Left]
      service right(server)[Right]
      left:R -- L:right
    MERMAID

    expect(Sirena.render(source)).to include('id="edge-left-right"')
  end
end
