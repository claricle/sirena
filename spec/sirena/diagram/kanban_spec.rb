# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Diagram::Kanban do
  describe '#valid?' do
    # Transform::Base#call (lib/sirena/transform/base.rb) now runs this
    # guard for every type, kanban included. A bare `kanban` header must
    # stay valid and keep rendering — the model-level check and the
    # Engine-level guarantee it backs are both asserted here so a future
    # change that makes either one reject an empty board goes red.
    it 'treats a bare board with no columns as valid, and Engine renders it' do
      expect(described_class.new.valid?).to be(true)
      expect(Sirena::Engine.new.render("kanban\n")).to include('<svg')
    end
  end

  describe Sirena::Diagram::KanbanColumn do
    describe '.attributes' do
      # A bare column carries only what the parser can give it: metadata a
      # column has no attribute for is dropped, and `label:` becomes the
      # title. This catches the model growing an attribute later, which
      # would silently change what a bare column holds.
      it 'defines no attribute a column metadata entry could land in' do
        expect(described_class.attributes.keys)
          .to contain_exactly(:id, :title, :cards)
      end
    end
  end
end
