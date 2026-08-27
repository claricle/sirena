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
  let(:svg) { described_class.new.render(source) }

  # Parses the document, so a malformed render fails here rather than in a
  # separate example that nothing can redden on its own.
  #
  # `element.text` is nil for an empty node, because a text node with no
  # content serializes as `<text></text>` (Sirena::Svg::Text#to_xml joins an
  # empty content collection). Normalizing with to_s keeps a missing label
  # comparing as "" rather than nil, so a failure reports the real difference.
  def rendered_text(xml)
    REXML::Document.new(xml).get_elements('//text').map { |e| e.text.to_s }
  end

  context 'with bare nodes (corpus 015, 016)' do
    let(:source) { "kanban\n    root\n      child1\n" }

    it 'renders the ids as labels' do
      # The middle "1" is the column's card-count badge: Transform::Kanban
      # supplies card_count and Renderer::Kanban emits it as its own text
      # node. It belongs in this list - do not trim it to two elements.
      expect(rendered_text(svg)).to eq(%w[root 1 child1])
    end
  end
end
