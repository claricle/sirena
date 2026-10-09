# frozen_string_literal: true

require_relative "notation_loader"

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
        NotationLoader.load_all(options[:require])
        puts "Supported diagram types:"

        Notation.plugins.each do |notation|
          puts
          puts "#{notation.id}:"
          notation.types.each { |type| puts "  #{type}" }
        end
      end
    end
  end
end
