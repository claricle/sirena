# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture, :aggregate_failures do
  subject(:services) do
    source = File.read(
      "spec/mermaid/architecture/architecture_external-4b070abb.mmd",
    )
    diagram = Sirena::Parser::Architecture.new.parse(source)
    described_class.new.call(diagram).children.to_h { |node| [node.id, node] }
  end

  it "distributes four disconnected services around the canvas" do
    expect(services["s3"].y).to be > services.values_at("ec2", "fa").map(&:y).max
    expect(services["api"].y).to be < services.values_at("ec2", "fa").map(&:y).min
    expect(services["ec2"].x).to be < services.values_at("s3", "api").map(&:x).min
    expect(services["fa"].x).to be > services.values_at("s3", "api").map(&:x).max
  end
end
