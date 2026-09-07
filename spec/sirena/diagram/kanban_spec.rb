# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Diagram::KanbanColumn do
  describe '.attributes' do
    # A bare column carries only what the parser can give it: metadata a
    # column has no attribute for is dropped, and `label:` becomes the
    # title. This catches the model growing an attribute later, which would
    # silently change what a bare column holds.
    it 'defines no attribute a column metadata entry could land in' do
      expect(described_class.attributes.keys)
        .to contain_exactly(:id, :title, :cards)
    end
  end
end
