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
          theme: options[:theme],
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
      # Text-mode reads tag their result with the locale's encoding and, under
      # `ruby -E ext:int`, transcode it first. The bytes are read raw instead
      # and `Source` reads them as UTF-8, as mmdc does; otherwise a UTF-8 file
      # under `LC_ALL=en_US.ISO8859-1` is drawn as mojibake.
      #
      # @return [String] Mermaid source code
      def read_input
        if file == '-' || file.nil?
          $stdin.binmode.read
        else
          File.binread(file)
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
          File.binwrite(options[:output], svg)
          puts "SVG written to #{options[:output]}" if options[:verbose]
        else
          print_svg(svg)
        end
      rescue Errno::EACCES
        raise ArgumentError,
              "Permission denied writing to: #{options[:output]}"
      end

      # UTF-8 to UTF-8, so the stream does not transcode to the locale's
      # encoding, or raise on a character it lacks.
      def print_svg(svg)
        $stdout.set_encoding(Encoding::UTF_8, Encoding::UTF_8)
        $stdout.write(svg, "\n")
      end
    end
  end
end
