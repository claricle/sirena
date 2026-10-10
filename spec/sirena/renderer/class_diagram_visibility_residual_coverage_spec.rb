# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::ClassDiagram do
  it "formats every visibility and defaults unknown values to public" do
    formatter_class = Class.new(described_class) do
      public :visibility_symbol
    end
    formatter = formatter_class.new
    visibilities = %w[public private protected package unknown]

    symbols = visibilities.to_h do |visibility|
      [visibility, formatter.visibility_symbol(visibility)]
    end

    expect(symbols).to eq(
      "public" => "+", "private" => "-", "protected" => "#",
      "package" => "~", "unknown" => "+"
    )
  end
end
