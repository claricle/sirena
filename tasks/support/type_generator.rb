# frozen_string_literal: true

require "erb"
require "fileutils"

module Sirena
  # Scaffolds a new Mermaid diagram type: the files that define it, their
  # specs, and its row in Notation::Mermaid::TYPES. One template set, no
  # options -- every type gets a layout, because the contract needs one.
  #
  # Raises {Error} before writing anything when the name is unusable; it
  # never exits, so the rake task decides what a failure looks like.
  class TypeGenerator
    class Error < StandardError; end

    TEMPLATES = File.expand_path("../templates/type", __dir__)
    TYPES_FILE = "lib/sirena/notation/mermaid.rb"
    NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/

    # Template => path under the root; %<type>s is the snake_case name.
    DEFINING_FILES = {
      "parser.rb.erb" => "lib/sirena/parser/%<type>s.rb",
      "grammar.rb.erb" => "lib/sirena/parser/grammars/%<type>s.rb",
      "builder.rb.erb" => "lib/sirena/parser/builders/%<type>s.rb",
      "diagram.rb.erb" => "lib/sirena/diagram/%<type>s.rb",
      "layout.rb.erb" => "lib/sirena/layout/%<type>s.rb",
      "renderer.rb.erb" => "lib/sirena/renderer/%<type>s.rb",
      "fixture.mmd.erb" => "spec/fixtures/contract/%<type>s.mmd",
    }.freeze

    SPEC_FILES = {
      "parser_spec.rb.erb" => "spec/sirena/parser/%<type>s_spec.rb",
      "diagram_spec.rb.erb" => "spec/sirena/diagram/%<type>s_spec.rb",
      "layout_spec.rb.erb" => "spec/sirena/layout/%<type>s_spec.rb",
      "renderer_spec.rb.erb" => "spec/sirena/renderer/%<type>s_spec.rb",
    }.freeze

    ROW_ANCHOR = "\n      }.freeze\n"

    # @param name [String] snake_case type name, also the diagram keyword
    # @param root [String] the repository root to write into
    # @param types [Hash] the registered rows, for collision checks
    def initialize(name, root:, types:)
      @type = name.to_s
      @root = root
      @types = types
    end

    # @return [Array<String>] paths written, relative to the root
    def call
      validate
      row_source = types_source_with_row
      paths = write_files(DEFINING_FILES.merge(SPEC_FILES))
      File.write(File.join(@root, TYPES_FILE), row_source)
      paths + [TYPES_FILE]
    end

    private

    def type
      @type
    end

    def klass
      @type.split("_").map(&:capitalize).join
    end

    def keyword
      @type
    end

    # Detection is case-insensitive, so the grammar must be too.
    def keyword_rule
      keyword.chars.map do |char|
        next "str(#{char.inspect})" unless char.match?(/[a-z]/)

        "match[\"#{char.upcase}#{char}\"]"
      end.join(" >> ")
    end

    def render(template)
      path = File.join(TEMPLATES, template)
      ERB.new(File.read(path), trim_mode: "-").result(binding)
    end

    def validate
      raise Error, "invalid type name: #{@type.inspect}" unless
        @type.match?(NAME_FORMAT)
      raise Error, "type already registered: #{@type}" if
        @types.key?(@type.to_sym)

      reject_existing_files
      reject_shadowing_row
    end

    def targets(files)
      files.values.map { |pattern| format(pattern, type: @type) }
    end

    def reject_existing_files
      taken = targets(DEFINING_FILES.merge(SPEC_FILES)).select do |path|
        File.exist?(File.join(@root, path))
      end
      raise Error, "would overwrite: #{taken.join(', ')}" unless taken.empty?
    end

    # TYPES is read in order, so an earlier row can claim this keyword.
    def reject_shadowing_row
      owner, = @types.find { |_, row| row[:pattern].match?("#{keyword}\n") }
      raise Error, "keyword #{keyword.inspect} is claimed by #{owner}" if owner
    end

    def types_source_with_row
      source = File.read(File.join(@root, TYPES_FILE))
      start = source.index("TYPES = {") or
        raise Error, "no TYPES table in #{TYPES_FILE}"
      anchor = source.index(ROW_ANCHOR, start) or
        raise Error, "no end of TYPES table in #{TYPES_FILE}"
      source.dup.insert(anchor + 1, row)
    end

    def row
      <<~RUBY.gsub(/^(?=.)/, "        ")
        #{@type}: {
          pattern: /\\A\\s*#{@type}(\\s|\\z)/i,
          keyword: "#{keyword}",
        },
      RUBY
    end

    # Renders everything first, so a template error leaves nothing behind.
    def write_files(files)
      rendered = files.to_h do |template, pattern|
        [format(pattern, type: @type), render(template)]
      end
      rendered.each do |relative, content|
        absolute = File.join(@root, relative)
        FileUtils.mkdir_p(File.dirname(absolute))
        File.write(absolute, content)
      end
      rendered.keys
    end
  end
end
