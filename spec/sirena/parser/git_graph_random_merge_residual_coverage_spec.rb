# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"

RSpec.describe Sirena::Parser::GitGraph do
  it "accepts both quote styles for a random merge option" do
    merges = ['random:"seed-a"', "random:'seed-b'"].map do |option|
      source = <<~MERMAID
        gitGraph
          commit
          branch side
          merge side #{option}
      MERMAID

      described_class.new.parse(source).commits.last
    end

    expect(merges).to all(
      have_attributes(is_merge: true, merge_branch: "side"),
    )
  end
end
