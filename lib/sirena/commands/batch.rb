# frozen_string_literal: true

require "fileutils"
require_relative "notation_loader"

module Sirena
  module Commands
    # Batch command for rendering multiple diagrams.
    #
    # Processes entire directories of diagram files and generates
    # corresponding SVG output files.
    class BatchCommand
      attr_reader :options

      def initialize(options = {})
        @options = options
        @stats = { success: 0, failed: 0, errors: [] }
      end

      # Execute the batch rendering command.
      #
      # @return [void]
      def run
        input_path = options[:input] || "."
        output_path = options[:output] || "output"
        print_header(input_path, output_path)
        NotationLoader.load_all(options[:require])
        files = find_diagram_files(input_path)
        return print_empty(input_path) if files.empty?

        render_batch(files, input_path, output_path)
      end

      # Whether every item rendered without error. Checked after #run, not
      # returned by it: #run's own contract (print the summary, survive a
      # bad file) is unrelated to whether the caller should exit non-zero,
      # and a boolean return on a method named `run` reads as a lie about
      # what it does.
      #
      # @return [Boolean] true if nothing failed (including a run that
      #   found no files at all)
      def success?
        @stats[:failed].zero?
      end

      private

      def render_batch(files, input_path, output_path)
        print_file_count(files)
        FileUtils.mkdir_p(output_path)
        process_files(files, input_path, output_path)
        print_summary
      end

      def print_header(input_path, output_path)
        puts "Sirena Batch Renderer"
        puts "=" * 60
        puts "Input:  #{input_path}"
        puts "Output: #{output_path}"
        puts "Theme:  #{options[:theme] || 'default'}"
        puts
      end

      def print_empty(input_path)
        puts "No diagram files found in: #{input_path}"
      end

      def print_file_count(files)
        puts "Found #{files.length} diagram files"
        puts
      end

      def process_files(files, input_path, output_path)
        files.each_with_index do |file, index|
          process_file(file, input_path, output_path, index + 1, files.length)
        end
      end

      def find_diagram_files(path)
        if File.directory?(path)
          extensions = batch_extensions
          Dir.glob(File.join(path, "**", "*")).select do |file|
            File.file?(file) && extensions.include?(File.extname(file).downcase)
          end
        elsif File.file?(path)
          [path]
        else
          []
        end
      end

      # Every registered notation's extensions, or only `--notation`'s.
      def batch_extensions
        return Notation.extensions unless options[:notation]

        Notation.fetch(options[:notation]).extensions
      end

      # Only a registered extension is swapped; any other name is kept.
      def output_name(relative)
        extension = File.extname(relative)
        return relative unless Notation.extensions.include?(extension.downcase)

        "#{relative.delete_suffix(extension)}.svg"
      end

      # `-i` names either a directory or a single file (`find_mermaid_files`
      # accepts both, and it's documented on the CLI). The directory case
      # strips `input_base` off the front of `file` to get a path relative
      # to it; a single file IS `input_base`, so that same subtraction
      # leaves '', turning `output_file` into the output directory itself.
      def relative_path_for(file, input_base)
        return File.basename(file) if File.file?(input_base)

        file.sub(/^#{Regexp.escape(input_base)}\/?/, "")
      end

      def process_file(file, input_base, output_base, current, total)
        relative = relative_path_for(file, input_base)
        output_file = File.join(output_base, output_name(relative))
        print "[#{current}/#{total}] #{relative}... "
        process_render(file, output_file, relative)
      end

      def process_render(file, output_file, relative)
        render_file(file, output_file)
        record_success
      rescue *Sirena::EXHAUSTION_ERRORS, StandardError => e
        record_failure(relative, e)
      end

      def render_file(file, output_file)
        # Raw bytes, as `RenderCommand#read_input` reads them: a text-mode
        # read would apply the locale's encodings before `Source` sees it.
        source = File.binread(file)
        svg = Sirena.render(source, **render_options(file))
        FileUtils.mkdir_p(File.dirname(output_file))
        File.binwrite(output_file, svg)
      end

      def render_options(file)
        {
          theme: options[:theme], verbose: options[:verbose], path: file,
          notation: options[:notation]
        }
      end

      def record_success
        @stats[:success] += 1
        puts "✅"
      end

      def record_failure(relative, error)
        @stats[:failed] += 1
        @stats[:errors] << { file: relative, error: error.message }
        puts "❌ #{error.class.name}"
        print_verbose_failure(error) if options[:verbose]
      end

      def print_verbose_failure(error)
        puts "   #{error.message}"
        # Printed, never stored: `@stats[:errors]` outlives the whole run,
        # and a cause's trace is what must not accumulate there.
        diagnostics = Sirena::ErrorReport.cause_diagnostics(error)
        return if diagnostics.empty?

        puts diagnostics.lines.map { |line| "   #{line}" }.join
      end

      def print_summary
        print_summary_header
        print_summary_counts
        print_errors if @stats[:failed].positive?
        print_success_rate
      end

      def print_summary_header
        puts "\n#{'=' * 60}"
        puts "BATCH RENDERING SUMMARY"
        puts "=" * 60
      end

      def print_summary_counts
        puts "✅ Success: #{@stats[:success]}"
        puts "❌ Failed:  #{@stats[:failed]}"
        puts "   Total:   #{@stats[:success] + @stats[:failed]}"
      end

      def print_errors
        puts "\nErrors:"
        @stats[:errors].first(5).each do |error|
          puts "  #{error[:file]}: #{error[:error].lines.first.strip}"
        end
        print_extra_error_count
        puts "\nUse --verbose to see full error details"
      end

      def print_extra_error_count
        return unless @stats[:errors].length > 5

        puts "  ... and #{@stats[:errors].length - 5} more errors"
      end

      def print_success_rate
        rate = (@stats[:success].to_f / (@stats[:success] + @stats[:failed]))
        puts "\nSuccess rate: #{(rate * 100).round(1)}%"
      end
    end
  end
end
