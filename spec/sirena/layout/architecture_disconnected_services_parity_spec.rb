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
    expect(disconnected_order).to all(be(true))
  end

  def disconnected_order
    middle_y = services.values_at("ec2", "fa").map(&:y)
    middle_x = services.values_at("s3", "api").map(&:x)
    [vertical_order(middle_y), horizontal_order(middle_x)].flatten
  end

  def vertical_order(middle_y)
    [services["s3"].y > middle_y.max, services["api"].y < middle_y.min]
  end

  def horizontal_order(middle_x)
    [services["ec2"].x < middle_x.min, services["fa"].x > middle_x.max]
  end
end
