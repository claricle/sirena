# frozen_string_literal: true

require "spec_helper"
require "sirena/lint_debt_scoreboard"

RSpec.describe Sirena::LintDebtScoreboard::Diff do
  subject(:text) { described_class.new(baseline:, current:).to_s }

  let(:baseline) do
    { ["Cop/A", "old.rb"] => 1, ["Cop/B", "changed.rb"] => 1 }
  end
  let(:current) do
    { ["Cop/A", "new.rb"] => 2, ["Cop/B", "changed.rb"] => 3 }
  end
  let(:expected) do
    "+ Cop/A new.rb: 2\n- Cop/A old.rb: 1\n~ Cop/B changed.rb: 1 -> 3"
  end

  it("formats every difference kind") { expect(text).to eq(expected) }
end
