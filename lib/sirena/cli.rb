# frozen_string_literal: true

require 'thor'

module Sirena
  # Command-line interface for sirena.
  #
  # Provides commands for rendering Mermaid diagrams to SVG and
  # managing diagram types.
  class Cli < Thor
    def self.exit_on_failure?
      true
    end

    desc 'render [FILE]', 'Render a Mermaid diagram to SVG'
    long_desc <<~DESC
      Renders a Mermaid diagram from FILE or stdin to SVG format.

      If FILE is not provided or is "-", reads from stdin.
      Output is written to stdout by default, or to the file specified
      with --output.

      Examples:
        sirena render diagram.mmd
        sirena render diagram.mmd --output diagram.svg
        sirena render diagram.mmd --theme dark
        sirena render diagram.mmd --theme /path/to/custom-theme.yml
        cat diagram.mmd | sirena render
        sirena render --verbose diagram.mmd
    DESC
    method_option :output,
                  aliases: '-o',
                  type: :string,
                  desc: 'Output file path (default: stdout)'
    method_option :format,
                  aliases: '-f',
                  type: :string,
                  default: 'svg',
                  desc: 'Output format (only svg supported)'
    method_option :theme,
                  aliases: '-t',
                  type: :string,
                  desc: 'Theme name or path to theme file ' \
                        '(default, dark, light, high_contrast)'
    method_option :verbose,
                  aliases: '-v',
                  type: :boolean,
                  default: false,
                  desc: 'Enable verbose output'
    def render(file = '-')
      require_relative 'commands/render'
      Commands::RenderCommand.new(file, options).run
    rescue StandardError => e
      handle_error(e)
    end

    desc 'types', 'List supported diagram types'
    long_desc <<~DESC
      Lists all diagram types currently supported by sirena.

      Examples:
        sirena types
    DESC
    def types
      require_relative 'commands/types'
      Commands::TypesCommand.new(options).run
    rescue StandardError => e
      handle_error(e)
    end

    desc 'batch', 'Batch render multiple Mermaid diagrams'
    long_desc <<~DESC
      Renders all Mermaid diagrams in a directory to SVG format.

      Recursively finds all .mmd files in the input directory and
      generates corresponding SVG files in the output directory.

      Examples:
        sirena batch --input docs/diagrams --output docs/images
        sirena batch -i diagrams -o output --theme dark
        sirena batch -i docs -o output -v
    DESC
    method_option :input,
                  aliases: '-i',
                  type: :string,
                  default: '.',
                  desc: 'Input directory or file'
    method_option :output,
                  aliases: '-o',
                  type: :string,
                  default: 'output',
                  desc: 'Output directory'
    method_option :theme,
                  aliases: '-t',
                  type: :string,
                  desc: 'Theme name or path to theme file'
    method_option :verbose,
                  aliases: '-v',
                  type: :boolean,
                  default: false,
                  desc: 'Enable verbose output'
    def batch
      require_relative 'commands/batch'
      Commands::BatchCommand.new(options).run
    rescue StandardError => e
      handle_error(e)
    end

    desc 'version', 'Show sirena version'
    long_desc <<~DESC
      Displays the current version of sirena.

      Examples:
        sirena version
    DESC
    def version
      require_relative 'commands/version'
      Commands::VersionCommand.new(options).run
    rescue StandardError => e
      handle_error(e)
    end

    # Make version available as --version flag
    map %w[--version -V] => :version

    private

    # Handles errors and exits with appropriate code.
    #
    # @param error [StandardError] the error to handle
    # @return [void]
    def handle_error(error)
      warn "Error: #{error.message}"
      warn error.backtrace.join("\n") if options[:verbose]
      exit 1
    end
  end
end
