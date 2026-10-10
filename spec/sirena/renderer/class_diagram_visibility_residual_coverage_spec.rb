# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::ClassDiagram do
  let(:formatter_class) do
    Class.new(described_class) do
      public :visibility_symbol
    end
  end
  let(:formatter) { formatter_class.new }
  let(:symbols) do
    %w[public private protected package unknown].to_h do |visibility|
      [visibility, formatter.visibility_symbol(visibility)]
    end
  end

  it "formats every visibility and defaults unknown values to public" do
    expect(symbols).to eq(
      "public" => "+", "private" => "-", "protected" => "#",
      "package" => "~", "unknown" => "+"
    )
  end
end
