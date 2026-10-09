# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A class, abstract class or interface and the Members of its
      # body, in the order they were written. `kind` is :class, :abstract or
      # :interface; `stereotypes` holds the text of each `<<...>>` and
      # `generics` the text of `<...>` after the name, or nil.
      class Klass
        attr_reader :name, :kind, :body, :stereotypes, :generics

        def initialize(name:, kind:, body:, stereotypes: [].freeze,
                       generics: nil)
          @name = name
          @kind = kind
          @body = body
          @stereotypes = stereotypes
          @generics = generics
          freeze
        end
      end
    end
  end
end
