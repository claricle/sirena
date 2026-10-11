# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Parser::GitGraph do
  def text_labels(svg)
    REXML::Document.new(svg).get_elements("//text").map(&:text)
  end

  cases = %w[
    should_support_cherry_picking_commits_with_no_ta-0234be84
    should_support_cherry_picking_of_merge_commits_w-670f4b6c
  ]

  cases.each do |case_name|
    it "parses empty tags as absent for #{case_name}" do
      source = File.read("spec/mermaid/gitgraph/#{case_name}.mmd")
      diagram = described_class.new.parse(source)

      expect(diagram.commits.select(&:is_cherry_pick).map(&:tag)).to all(be_nil)
    end

    it "matches the pinned reference for #{case_name}" do
      source = File.read("spec/mermaid/gitgraph/#{case_name}.mmd")
      reference = File.read("spec/fixtures_mermaid/gitgraph/#{case_name}.svg")

      labels = text_labels(reference) + text_labels(Sirena.render(source))
      expect(labels).not_to include('""')
    end
  end
end
