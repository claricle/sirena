# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A class, abstract class or interface and the Members of its
      # body, in the order they were written. `kind` is :class, :abstract or
      # :interface.
      class Klass
        attr_reader :name, :kind, :body

        def initialize(name:, kind:, body:)
          @name = name
          @kind = kind
          @body = body
          freeze
        end
      end
    end
  end
end
