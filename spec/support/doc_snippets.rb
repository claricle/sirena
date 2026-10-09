# frozen_string_literal: true

require "shellwords"
require "sirena/cli"
require "stringio"
require "tmpdir"

# Extracts the `[source,...]` blocks of an AsciiDoc file and runs them.
module DocSnippets
  Block = Struct.new(:path, :line, :lang, :body)

  # Blocks that are not executed, each with the reason. Keyed by the
  # first line of the block body.
  SKIPPED = {
    "gem 'sirena'" => "a Gemfile line, not Ruby to run",
    "bundle install" => "installs the bundle, not part of the library",
    "gem install sirena" => "installs the published gem",
    "Mermaid Syntax Input (String)" => "ASCII-art pipeline diagram",
    "Sirena (Root Module)" => "ASCII-art component tree",
    "git clone https://github.com/claricle/sirena.git" =>
      "clones the repository",
    %(echo 'export PATH="$HOME/.gem/ruby/X.X.0/bin:$PATH"' >> ~/.bashrc) =>
      "edits the reader's shell profile",
    "gem install sirena --user-install" => "installs the published gem",
    "sirena render [FILE]" => "usage synopsis with a placeholder",
    "sirena batch [OPTIONS]" => "usage synopsis with a placeholder",
    "sirena types [OPTIONS]" => "usage synopsis with a placeholder",
    "sirena render --notation mermaid diagram.txt" =>
      "needs ./my_notation.rb, a notation file the reader writes",
    "sirena batch -i diagrams -o output" =>
      "needs ./my_notation.rb, a notation file the reader writes",
    "# Run Mermaid.js compatibility tests" =>
      "rake task and mermaid-cli comparison, not the sirena CLI",
  }.freeze

  ROOT = File.expand_path("../..", __dir__)

  README = File.join(ROOT, "README.adoc")

  GUIDES = [
    "docs/_guides/cli-reference.adoc",
    "docs/_guides/installation.adoc",
    "docs/_guides/quick-start.adoc",
    "docs/_pages/compatibility.adoc",
    "docs/index.adoc",
  ].map { |f| File.join(ROOT, f) }.freeze

  # Languages whose blocks are commands or code to run.
  RUNNABLE = %w[ruby shell bash].freeze

  SOURCE_MARKER = /\A\[source(?:,(\w+))?\]\s*\z/

  DIAGRAM = "graph TD\n  A[Start] --> B[Process]\n  B --> C[End]\n"

  module_function

  def blocks(path = README)
    lines = File.read(path).lines(chomp: true)
    lines.each_index.filter_map { |index| block_at(path, lines, index) }
  end

  def block_at(path, lines, index)
    marker = SOURCE_MARKER.match(lines[index])
    return unless marker && lines[index + 1] == "----"

    body = lines[(index + 2)..].take_while { |l| l != "----" }
    Block.new(path, index + 1, marker[1], body.join("\n"))
  end

  def block_containing(text, path = README)
    blocks(path).find { |b| b.body.include?(text) }
  end

  def skipped_keys_without_block(paths = [README, *GUIDES])
    SKIPPED.keys - paths.flat_map { |p| blocks(p) }.map { |b| first_line(b) }
  end

  def first_line(block)
    block.body.lines.first.to_s.strip
  end

  def skip_reason(block)
    SKIPPED[first_line(block)]
  end

  # Runs one block in a scratch directory holding the files the
  # README's examples refer to; returns the files it left behind.
  def run(block)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        write_fixtures
        run_in_cwd(block)
        Dir.glob("**/*").select { |f| File.file?(f) }
      end
    end
  end

  # The files the docs' examples refer to.
  def write_fixtures
    %w[input_dir diagrams].each do |dir|
      Dir.mkdir(dir)
      File.write("#{dir}/one.mmd", DIAGRAM)
    end
    %w[diagram.mmd my-first-diagram.mmd diagram.txt].each do |f|
      File.write(f, DIAGRAM)
    end
  end

  def run_in_cwd(block)
    case block.lang
    when "ruby"
      TOPLEVEL_BINDING.dup.eval(block.body, File.basename(block.path),
                                block.line)
    when "shell", "bash" then block.body.each_line { |l| shell(l) }
    else raise ArgumentError, "unhandled block language: #{block.lang.inspect}"
    end
  end

  def shell(line)
    return if line.strip.empty? || line.lstrip.start_with?("#")

    piped = line.match(/\Acat (\S+) \| (.*)/m)
    return with_stdin(File.read(piped[1])) { shell(piped[2]) } if piped

    with_quiet_stdout { Sirena::Cli.start(sirena_args(line)) }
  end

  def sirena_args(line)
    command, *args = Shellwords.split(line)
    return args if command == "sirena"

    raise ArgumentError, "only the sirena CLI is run, got #{line.inspect}"
  end

  def with_stdin(text)
    saved = $stdin
    $stdin = StringIO.new(text)
    yield
  ensure
    $stdin = saved
  end

  def with_quiet_stdout
    saved = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = saved
  end
end
