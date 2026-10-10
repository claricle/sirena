# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Edge do
  let(:source_error) { ["source_id must be nonempty"] }
  let(:target_error) { ["target_id must be nonempty"] }

  def validation_messages(source_id, target_id)
    described_class.new(
      id: "edge", source_id: source_id, target_id: target_id,
    ).validate.map(&:message)
  end

  def source_messages(source_id)
    validation_messages(source_id, "target")
  end

  def target_messages(target_id)
    validation_messages("source", target_id)
  end

  it "reports nil and empty source identities" do
    messages = [nil, ""].map { |source_id| source_messages(source_id) }

    expect(messages).to eq([source_error, source_error])
  end

  it "reports nil and empty target identities" do
    messages = [nil, ""].map { |target_id| target_messages(target_id) }

    expect(messages).to eq([target_error, target_error])
  end
end
