# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # A `namespace Name { ... }` block of a class diagram: the box mmdc
    # draws around the classes written inside it.
    class ClassNamespace < Lutaml::Model::Serializable
      # The namespace name, as written
      attribute :name, :string

      # The ids of the entities declared inside the block
      attribute :class_ids, :string, collection: true, default: -> { [] }
    end
  end
end
