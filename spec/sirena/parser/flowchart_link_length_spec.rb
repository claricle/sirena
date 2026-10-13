# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart do
  link_shapes = [
    ["solid with head", "arrow", (2..4).map { |length| "#{'-' * length}>" }],
    ["solid without head", "line", (3..5).map { |length| "-" * length }],
    ["thick with head", "thick_arrow",
     (2..4).map { |length| "#{'=' * length}>" }],
    ["thick without head", "thick_line", (3..5).map { |length| "=" * length }],
    ["dotted with head", "dotted_arrow",
     (1..3).map { |length| "-#{'.' * length}->" }],
    ["dotted without head", "dotted_line",
     (1..3).map { |length| "-#{'.' * length}-" }],
  ]

  link_shapes.each do |shape, expected_type, links|
    links.each do |link|
      context "with #{shape} link #{link.inspect}" do
        let(:source) { "flowchart TD\n  A#{link}B\n" }
        let(:diagram) { described_class.new.parse(source) }

        it "keeps the arrow type identical across lengths" do
          expect(diagram.edges.fetch(0).arrow_type)
            .to eq(expected_type), "source #{source.inspect}"
        end
      end
    end
  end
end
