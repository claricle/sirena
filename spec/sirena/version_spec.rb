# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  let(:source) { File.expand_path("../../lib/sirena/version.rb", __dir__) }

  before do
    stub_const("Sirena", Module.new)
    load source
  end

  it("exposes its loaded version") do
    expect(Object.const_get(:Sirena).const_get(:VERSION)).to eq("0.1.0")
  end
end
