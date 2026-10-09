# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # One compared element of a figure: {kind, key, parent, bbox, label}.
    # `identity` says whether `key` is an id the author wrote (:id) or a label
    # or ordinal fallback (:label), so the matcher can fall back to labels
    # when only one side exposes an id (contract section 1).
    class Element
      attr_reader :kind, :key, :identity, :parent, :bbox, :label

      def initialize(kind:, key:, bbox:, label: nil, identity: :id, parent: nil)
        @kind = kind
        @key = key
        @identity = identity
        @bbox = bbox
        @label = label
        @parent = parent
      end

      def with_parent(parent_key)
        self.class.new(kind: kind, key: key, bbox: bbox, label: label, identity: identity, parent: parent_key)
      end
    end
  end
end
