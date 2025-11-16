# frozen_string_literal: true

module Sirena
  module Commands
    # Command to render Mermaid diagrams to SVG.
    class RenderCommand
      attr_reader :file, :options

      # Creates a new render command.
      #
      # @param file [String] input file path or '-' for stdin
      # @param options [Hash] command options
      def initialize(file, options = {})
        @file = file
        @options = options
      end

      # Executes the render command.
      #
      # @return [void]
      def run
        validate_format!

        source = read_input
        engine = Engine.new(
          verbose: options[:verbose],
          theme: options[:theme]
        )
        svg = engine.render(source)

        write_output(svg)
      end

      private

      # Validates the output format option.
      #
      # @return [void]
      # @raise [ArgumentError] if format is not supported
      def validate_format!
        return if options[:format] == 'svg'

        raise ArgumentError,
              "Unsupported format: #{options[:format]}. " \
              'Only SVG format is currently supported.'
      end

      # Reads input from file or stdin.
      #
      # @return [String] Mermaid source code
      def read_input
        if file == '-' || file.nil?
          $stdin.read
        else
          File.read(file)
        end
      rescue Errno::ENOENT
        raise ArgumentError, "File not found: #{file}"
      rescue Errno::EACCES
        raise ArgumentError, "Permission denied: #{file}"
      end

      # Writes output to file or stdout.
      #
      # @param svg [String] SVG content
      # @return [void]
      def write_output(svg)
        if options[:output]
          File.write(options[:output], svg)
          puts "SVG written to #{options[:output]}" if options[:verbose]
        else
          puts svg
        end
      rescue Errno::EACCES
        raise ArgumentError,
              "Permission denied writing to: #{options[:output]}"
      end
    end
  end
end
