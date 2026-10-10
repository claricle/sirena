# frozen_string_literal: true

require "thor"

module Sirena
  # Command-line interface for sirena.
  #
  # Provides commands for rendering diagrams to SVG and
  # managing diagram types.
  class Cli < Thor
    def self.exit_on_failure?
      true
    end

    desc "render [FILE]", "Render a diagram to SVG"
    long_desc <<~DESC
      Renders a diagram from FILE or stdin to SVG format.

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
        sirena render --notation mermaid diagram.txt
        sirena render --require ./my_notation.rb diagram.my
    DESC
    method_option :output,
                  aliases: "-o",
                  type: :string,
                  desc: "Output file path (default: stdout)"
    method_option :format,
                  aliases: "-f",
                  type: :string,
                  default: "svg",
                  desc: "Output format (only svg supported)"
    method_option :theme,
                  aliases: "-t",
                  type: :string,
                  desc: "Theme name or path to theme file " \
                        "(default, dark, light, high_contrast)"
    method_option :verbose,
                  aliases: "-v",
                  type: :boolean,
                  default: false,
                  desc: "Enable verbose output"
    method_option :notation,
                  type: :string,
                  desc: "Notation to use (default: detected from the " \
                        "file extension, then the source)"
    method_option :require,
                  aliases: "-r",
                  type: :string,
                  repeatable: true,
                  desc: "Load a notation file before rendering " \
                        "(repeatable, like ruby -r)"
    def render(file = "-")
      require_relative "commands/render"
      Commands::RenderCommand.new(file, options).run
    rescue *EXHAUSTION_ERRORS, StandardError => e
      # `RenderCommand#run` builds the theme (a hostile `--theme` YAML
      # file) and reads the input file BEFORE `Engine#render` is ever
      # called, so both sit outside the engine's own widened rescue.
      # `EXHAUSTION_ERRORS` are not `StandardError`, so without naming
      # them here the CLI process goes down raw instead of printing an
      # error and exiting 1, exactly like an unguarded `batch` used to.
      handle_error(e)
    end

    desc "types", "List supported diagram types"
    long_desc <<~DESC
      Lists all diagram types currently supported by sirena.

      Examples:
        sirena types
        sirena types --require ./my_notation.rb
    DESC
    method_option :require,
                  aliases: "-r",
                  type: :string,
                  repeatable: true,
                  desc: "Load a notation file first (repeatable, like ruby -r)"
    def types
      require_relative "commands/types"
      Commands::TypesCommand.new(options).run
    rescue StandardError => e
      handle_error(e)
    end

    desc "batch", "Batch render multiple diagrams"
    long_desc <<~DESC
      Renders all diagrams in a directory to SVG format.

      Recursively finds every file with a registered notation's extension
      (or only --notation's) in the input directory and generates
      corresponding SVG files in the output directory.

      Examples:
        sirena batch --input docs/diagrams --output docs/images
        sirena batch -i diagrams -o output --theme dark
        sirena batch -i docs -o output -v
        sirena batch -i docs -o output --notation mermaid
    DESC
    method_option :input,
                  aliases: "-i",
                  type: :string,
                  default: ".",
                  desc: "Input directory or file"
    method_option :output,
                  aliases: "-o",
                  type: :string,
                  default: "output",
                  desc: "Output directory"
    method_option :theme,
                  aliases: "-t",
                  type: :string,
                  desc: "Theme name or path to theme file"
    method_option :verbose,
                  aliases: "-v",
                  type: :boolean,
                  default: false,
                  desc: "Enable verbose output"
    method_option :notation,
                  type: :string,
                  desc: "Notation to use (default: detected from the " \
                        "file extension, then the source)"
    method_option :require,
                  aliases: "-r",
                  type: :string,
                  repeatable: true,
                  desc: "Load a notation file before rendering " \
                        "(repeatable, like ruby -r)"
    def batch
      require_relative "commands/batch"
      command = Commands::BatchCommand.new(options)
      command.run
      exit 1 unless command.success?
    rescue StandardError => e
      handle_error(e)
    end

    desc "version", "Show sirena version"
    long_desc <<~DESC
      Displays the current version of sirena.

      Examples:
        sirena version
    DESC
    def version
      require_relative "commands/version"
      Commands::VersionCommand.new(options).run
    rescue StandardError => e
      handle_error(e)
    end

    # Make version available as --version flag
    map %w[--version -V] => :version

    private

    # Handles errors and exits with appropriate code.
    #
    # @param error [StandardError, SystemStackError, NoMemoryError]
    #   the error to handle
    # @return [void]
    def handle_error(error)
      warn "Error: #{error.message}"
      report_verbose_error(error) if options[:verbose]
      exit 1
    end

    def report_verbose_error(error)
      # `backtrace` is nil when the VM fails an allocation before it can
      # even build one -- `NoMemoryError` from `File.read` or a hostile
      # `--theme` reaches this method through the rescue above, and
      # `--verbose` on that failure must not itself crash the CLI.
      warn error.backtrace&.join("\n")
      diagnostics = ErrorReport.cause_diagnostics(error)
      warn diagnostics unless diagnostics.empty?
    end
  end
end
