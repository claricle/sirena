# frozen_string_literal: true

require_relative "style/colour"
require_relative "style/inline"
require_relative "style/sheet"
require_relative "style/reader"
require_relative "style/bound"

module Sirena
  module Notation
    module PlantUML
      # One reading of how a PlantUML diagram is styled, shared by every
      # family: {Reader} turns the source's `skinparam` lines and `<style>`
      # blocks into a {Sheet}, and a renderer asks the sheet for the value
      # of a property instead of keeping its own palette.
      module Style
        extend self

        # @param element [Symbol, nil] the element kind, nil for a bare
        #   stereotype
        # @param stereotype [String, nil] the stereotype, without `<<>>`
        # @return [String] the key a rule is stored under
        def selector(element, stereotype = nil)
          return element.to_s unless stereotype

          name = stereotype.downcase
          element ? "#{element}<<#{name}>>" : ".#{name}"
        end
      end
    end
  end
end
