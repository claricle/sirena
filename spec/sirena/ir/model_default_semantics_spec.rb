# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Model do
  it("has no default semantic errors") { expect(described_class.new).to be_valid }
end
