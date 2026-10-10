# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::ErEntity do
  it "is invalid without an attribute collection" do
    entity = described_class.new(id: "CUSTOMER", name: "CUSTOMER")
    entity.attributes = nil
    expect(entity).not_to be_valid
  end
end
