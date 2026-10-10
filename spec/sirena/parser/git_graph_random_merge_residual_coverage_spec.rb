# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"

RSpec.describe Sirena::Parser::GitGraph do
  let(:merges) do
    ['random:"seed-a"', "random:'seed-b'"].map do |option|
      source = <<~MERMAID
        gitGraph
          commit
          branch side
          merge side #{option}
      MERMAID

      described_class.new.parse(source).commits.last
    end
  end

  it "accepts both quote styles for a random merge option" do
    expect(merges).to all(
      have_attributes(is_merge: true, merge_branch: "side"),
    )
  end
end
