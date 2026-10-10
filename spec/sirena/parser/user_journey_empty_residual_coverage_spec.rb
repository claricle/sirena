# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::UserJourney do
  it "parses a bare journey header as an empty diagram" do
    diagram = described_class.new.parse("journey\n")

    expect(diagram).to have_attributes(title: nil, sections: [])
  end
end
