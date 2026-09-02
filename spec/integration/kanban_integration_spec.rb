# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'

# Deliberately shaped unlike its siblings in spec/integration/: they wire
# Parser -> Transform -> Renderer by hand and none of them calls Engine#render.
# The corpus pass predicate is Engine-to-XML, so this one drives that path
# instead, which is the only place the whole pipeline is exercised for kanban.
# (The siblings predate the RSpec/DescribeClass cop and are grandfathered in
# .rubocop_todo.yml; new files are not, so this one names the class it drives.)
RSpec.describe Sirena::Engine do
  let(:xml) { described_class.new.render(source) }

  # Parsing here means a malformed render fails on the assertion below,
  # rather than in a separate example nothing can redden on its own.
  #
  # `.to_s` because an empty node serializes as `<text></text>` and comes
  # back as nil, which would compare against "" and misreport the difference.
  def rendered_text(document)
    REXML::Document.new(document).get_elements('//text').map { |e| e.text.to_s }
  end

  context 'with bare nodes (corpus 016)' do
    let(:source) { "kanban\n    root\n      child1\n      child2\n" }

    it 'renders each id as its label, around the column card count' do
      expect(rendered_text(xml)).to eq(%w[root 2 child1 child2])
    end
  end

  context 'with identical bare cards in one column' do
    # The parser spec pins that three lines survive as three KanbanCards, but
    # those three are value-equal under lutaml-model, so any later `uniq`,
    # `Set` or `Hash` key between the model and the SVG would collapse them
    # with no parser-level assertion able to notice. This asserts the drawn
    # result instead: three card labels reach the document, and the column
    # header still counts three.
    let(:source) { "kanban\n  col\n    a\n    a\n    a\n" }

    it 'draws one card per source line' do
      expect(rendered_text(xml)).to eq(%w[col 3 a a a])
    end
  end
end
