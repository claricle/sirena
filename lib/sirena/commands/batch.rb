# frozen_string_literal: true

require 'fileutils'

module Sirena
  module Commands
    # Batch command for rendering multiple Mermaid diagrams.
    #
    # Processes entire directories of .mmd files and generates
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
        input_path = options[:input] || '.'
        output_path = options[:output] || 'output'

        puts "Sirena Batch Renderer"
        puts "=" * 60
        puts "Input:  #{input_path}"
        puts "Output: #{output_path}"
        puts "Theme:  #{options[:theme] || 'default'}"
        puts

        files = find_mermaid_files(input_path)

        if files.empty?
          puts "No .mmd files found in: #{input_path}"
          return
        end

        puts "Found #{files.length} diagram files"
        puts

        FileUtils.mkdir_p(output_path)

        files.each_with_index do |file, idx|
          process_file(file, input_path, output_path, idx + 1, files.length)
        end

        print_summary
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

      def find_mermaid_files(path)
        if File.directory?(path)
          Dir.glob(File.join(path, '**', '*.mmd'))
        elsif File.file?(path)
          [path]
        else
          []
        end
      end

      # `-i` names either a directory or a single file (`find_mermaid_files`
      # accepts both, and it's documented on the CLI). The directory case
      # strips `input_base` off the front of `file` to get a path relative
      # to it; a single file IS `input_base`, so that same subtraction
      # leaves '', turning `output_file` into the output directory itself.
      def relative_path_for(file, input_base)
        return File.basename(file) if File.file?(input_base)

        file.sub(/^#{Regexp.escape(input_base)}\/?/, '')
      end

      def process_file(file, input_base, output_base, current, total)
        relative = relative_path_for(file, input_base)
        output_file = File.join(output_base, relative.sub(/\.mmd$/, '.svg'))

        print "[#{current}/#{total}] #{relative}... "

        begin
          source = File.read(file)
          svg = Sirena.render(source,
                             theme: options[:theme],
                             verbose: options[:verbose])

          FileUtils.mkdir_p(File.dirname(output_file))
          File.write(output_file, svg)

          @stats[:success] += 1
          puts "✅"
        rescue *Sirena::EXHAUSTION_ERRORS, StandardError => e
          # Batch promises to survive a bad file and report it. `File.read`
          # runs inside this block too, so exhaustion can arrive from
          # outside the engine's own boundary and has to be named here as
          # well as there.
          @stats[:failed] += 1
          @stats[:errors] << { file: relative, error: e.message }
          puts "❌ #{e.class.name}"
          if options[:verbose]
            puts "   #{e.message}"
            # Printed, never stored: `@stats[:errors]` above outlives the
            # whole run, and a cause's trace is what must not accumulate
            # there.
            diagnostics = Sirena::ErrorReport.cause_diagnostics(e)
            puts diagnostics.lines.map { |l| "   #{l}" }.join unless diagnostics.empty?
          end
        end
      end

      def print_summary
        puts "\n" + "=" * 60
        puts "BATCH RENDERING SUMMARY"
        puts "=" * 60
        puts "✅ Success: #{@stats[:success]}"
        puts "❌ Failed:  #{@stats[:failed]}"
        puts "   Total:   #{@stats[:success] + @stats[:failed]}"

        if @stats[:failed] > 0
          puts "\nErrors:"
          @stats[:errors].first(5).each do |err|
            puts "  #{err[:file]}: #{err[:error].lines.first.strip}"
          end
          if @stats[:errors].length > 5
            puts "  ... and #{@stats[:errors].length - 5} more errors"
          end
          puts "\nUse --verbose to see full error details"
        end

        if @stats[:success] + @stats[:failed] > 0
          success_rate = (@stats[:success].to_f /
                         (@stats[:success] + @stats[:failed]) * 100).round(1)
          puts "\nSuccess rate: #{success_rate}%"
        end
      end
    end
  end
end