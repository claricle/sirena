# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A class, abstract class or interface and the Members of its
      # body, in the order they were written. `kind` is :class, :abstract or
      # :interface.
      Klass = Data.define(:name, :kind, :body)
    end
  end
end
