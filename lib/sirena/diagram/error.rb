# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Error diagram model.
    #
    # Represents a simple error diagram that displays error messages or
    # error states. Error diagrams are typically used to show parsing
    # errors, syntax errors, or system failure states.
    #
    # @example Creating an error diagram
    #   error = Error.new
    #   error.message = "Syntax Error"
    class Error < Base
      # Error message to display
      attribute :message, :string

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :error
      def diagram_type
        :error
      end

      # Validates the error diagram structure.
      #
      # Error diagrams are always valid as they have no required content.
      #
      # @return [Boolean] true
      def valid?
        true
      end
    end
  end
end