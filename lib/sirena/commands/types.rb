# frozen_string_literal: true

module Sirena
  module Commands
    # Command to list supported diagram types.
    class TypesCommand
      attr_reader :options

      # Creates a new types command.
      #
      # @param options [Hash] command options
      def initialize(options = {})
        @options = options
      end

      # Executes the types command.
      #
      # @return [void]
      def run
        puts 'Supported diagram types:'
        puts

        DiagramRegistry.types.each do |type|
          puts "  #{type}"
        end
      end
    end
  end
end
