# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Info diagram model.
    #
    # Represents a simple informational diagram that displays a message
    # or status information. Info diagrams are typically used to show
    # system information, help text, or status messages.
    #
    # @example Creating an info diagram
    #   info = Info.new
    #   info.show_info = true
    class Info < Base
      # Whether to show additional info
      attribute :show_info, :boolean, default: -> { false }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :info
      def diagram_type
        :info
      end

      # Validates the info diagram structure.
      #
      # Info diagrams are always valid as they have no required content.
      #
      # @return [Boolean] true
      def valid?
        true
      end
    end
  end
end