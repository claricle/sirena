# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # One line of a class body.
      #
      # `kind` is :field or :method. `visibility` is :public, :private,
      # :protected, :package, or nil when the line carries no marker.
      # `parameters` is the text between a method's parentheses and is nil
      # for a field. `type` is the text after `:` or nil.
      class Member
        attr_reader :kind, :visibility, :name, :type, :parameters

        def initialize(kind:, visibility:, name:, type:, parameters:)
          @kind = kind
          @visibility = visibility
          @name = name
          @type = type
          @parameters = parameters
          freeze
        end
      end
    end
  end
end
