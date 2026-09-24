# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Diagram::KanbanColumn do
  describe '.attributes' do
    # A bare column carries only what the parser can give it: metadata a
    # column has no attribute for is dropped, and `label:` becomes the
    # title. `icon` and `classes` now DO land on a column, but from
    # different sources: `icon` from `@{ icon: ... }` metadata on the
    # column's own item line (see the 'with metadata on a bare top-level
    # node' parser context) OR a standalone `::icon(...)` line right after
    # it; `classes` ONLY from a standalone `:::className` directive line -
    # mermaid does not read a `classes` key out of `@{ ... }` metadata at
    # all (Builders::Kanban::BoardBuilder#apply_modifier / #parse_metadata).
    # This catches the model growing a further attribute later, which would
    # silently change what a bare column holds.
    it 'defines exactly the attributes a column metadata entry can land in' do
      expect(described_class.attributes.keys)
        .to contain_exactly(:id, :title, :icon, :classes, :cards)
    end
  end
end
