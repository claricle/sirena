# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # One line of a class body.
      #
      # `kind` is :field or :method. `visibility` is :public, :private,
      # :protected, :package, or nil when the line carries no marker.
      # `parameters` is the text between a method's parentheses and is nil
      # for a field and for a `{method}` written without parentheses. `type`
      # is the declared type or nil. `type_position` preserves whether that
      # type preceded the name or followed `:`; it defaults to :suffix for
      # callers and older IR that do not record the distinction. `modifiers`
      # holds :abstract and :static as written.
      class Member
        attr_reader :kind, :visibility, :name, :type, :parameters, :modifiers,
                    :type_position

        # @param detail [Hash] optional `:parameters`, nil by default, and
        #   `:modifiers`, empty by default
        def initialize(kind:, visibility:, name:, type:, **detail)
          @kind = kind
          @visibility = visibility
          @name = name
          @type = type
          @parameters = detail[:parameters]
          @modifiers = detail.fetch(:modifiers, [].freeze)
          @type_position = detail.fetch(:type_position, :suffix)
          freeze
        end
      end
    end
  end
end
