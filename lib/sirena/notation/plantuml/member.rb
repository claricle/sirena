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
      Member = Data.define(:kind, :visibility, :name, :type, :parameters)
    end
  end
end
