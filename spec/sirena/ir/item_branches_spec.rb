# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Item do
  let(:identity_error) { ["id must be a nonempty String"] }
  let(:properties_error) { ["properties must be a valid PropertySet"] }
  let(:nested_properties_error) do
    ["weight must be finite and nonnegative", *properties_error]
  end

  def validation_messages(id:, properties: Sirena::IR::PropertySet.new)
    described_class.new(id: id, properties: properties).validate.map(&:message)
  end

  it "reports nil and empty identities" do
    messages = [nil, ""].map { |id| validation_messages(id: id) }

    expect(messages).to eq([identity_error, identity_error])
  end

  it "reports absent and invalid property sets" do
    invalid = Sirena::IR::PropertySet.new(weight: -1)
    messages = [nil, invalid].map do |properties|
      validation_messages(id: "item", properties: properties)
    end

    expect(messages).to eq([properties_error, nested_properties_error])
  end
end
