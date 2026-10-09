# frozen_string_literal: true

require "shellwords"
require "sirena/cli"
require "stringio"
require "tmpdir"

# Extracts the `[source,...]` blocks of an AsciiDoc file and runs them.
module DocSnippets
  Block = Struct.new(:line, :lang, :body)

  # Blocks that are not executed, each with the reason. Keyed by the
  # first line of the block body.
  SKIPPED = {
    "gem 'sirena'" => "a Gemfile line, not Ruby to run",
    "bundle install" => "installs the bundle, not part of the library",
    "gem install sirena" => "installs the published gem",
    "Mermaid Syntax Input (String)" => "ASCII-art pipeline diagram",
    "Sirena (Root Module)" => "ASCII-art component tree",
  }.freeze

  README = File.expand_path("../../README.adoc", __dir__)

  SOURCE_MARKER = /\A\[source(?:,(\w+))?\]\z/

  DIAGRAM = "graph TD\n  A[Start] --> B[Process]\n  B --> C[End]\n"

  module_function

  def blocks(path = README)
    lines = File.read(path).lines(chomp: true)
    lines.each_index.filter_map { |index| block_at(lines, index) }
  end

  def block_at(lines, index)
    marker = SOURCE_MARKER.match(lines[index])
    return unless marker && lines[index + 1] == "----"

    body = lines[(index + 2)..].take_while { |l| l != "----" }
    Block.new(index + 1, marker[1], body.join("\n"))
  end

  def block_containing(text)
    blocks.find { |b| b.body.include?(text) }
  end

  def skipped_keys_without_block
    SKIPPED.keys - blocks.map { |b| b.body.lines.first.to_s.strip }
  end

  def skip_reason(block)
    SKIPPED[block.body.lines.first.to_s.strip]
  end

  # Runs one block in a scratch directory holding the files the
  # README's examples refer to; returns the files it left behind.
  def run(block)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("diagram.mmd", DIAGRAM)
        Dir.mkdir("input_dir")
        File.write("input_dir/one.mmd", DIAGRAM)
        run_in_cwd(block)
        Dir.glob("**/*").select { |f| File.file?(f) }
      end
    end
  end

  def run_in_cwd(block)
    case block.lang
    when "ruby"
      TOPLEVEL_BINDING.dup.eval(block.body, "README.adoc", block.line)
    when "shell" then block.body.each_line { |l| shell(l) }
    else raise ArgumentError, "unhandled block language: #{block.lang.inspect}"
    end
  end

  def shell(line)
    command, *args = Shellwords.split(line)
    unless command == "sirena"
      raise ArgumentError, "only the sirena CLI is run, got #{line.inspect}"
    end

    with_quiet_stdout { Sirena::Cli.start(args) }
  end

  def with_quiet_stdout
    saved = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = saved
  end
end
