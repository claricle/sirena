# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::FlowchartParser do
  link_shapes = [
    ['solid with head', 'arrow', (2..4).map { |length| "#{'-' * length}>" }],
    ['solid without head', 'line', (3..5).map { |length| '-' * length }],
    ['thick with head', 'thick_arrow', (2..4).map { |length| "#{'=' * length}>" }],
    ['thick without head', 'thick_line', (3..5).map { |length| '=' * length }],
    ['dotted with head', 'dotted_arrow', (1..3).map { |length| "-#{'.' * length}->" }],
    ['dotted without head', 'dotted_line', (1..3).map { |length| "-#{'.' * length}-" }]
  ]

  link_shapes.each do |shape, expected_type, links|
    it "keeps #{shape} identical across lengths" do
      observed_types = {}

      aggregate_failures do
        links.each do |link|
          source = "flowchart TD\n  A#{link}B\n"
          diagram = nil
          message = "source #{source.inspect}"

          expect { diagram = described_class.new.parse(source) }
            .not_to raise_error, message
          next unless diagram

          arrow_type = diagram.edges.fetch(0).arrow_type
          observed_types[source] = arrow_type
          expect(arrow_type).to eq(expected_type), message
        end

        reference_type = observed_types.values.first
        observed_types.each do |source, arrow_type|
          expect(arrow_type).to eq(reference_type), "source #{source.inspect}"
        end
      end
    end
  end
end
