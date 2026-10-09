# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "support/fake_notation"
require "support/isolated_notation_registry"
require "stringio"
require "sirena/cli"

# Helpers that drive the CLI in-process and capture what it printed.
module NotationCliHelpers
  def write(name, content = flowchart)
    File.join(dir, name).tap do |path|
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  # @return [Array(String, String, Integer, nil)] stdout, stderr, exit status
  def run_cli(*args)
    status = nil
    out = StringIO.new
    err = StringIO.new
    original = [$stdout, $stderr]
    $stdout = out
    $stderr = err
    begin
      Sirena::Cli.start(args)
    rescue SystemExit => e
      status = e.status
    end
    [out.string, err.string, status]
  ensure
    $stdout, $stderr = original
  end

  # Its `parse` takes any source, so only the extension can have chosen it.
  def register_unclaiming_fake
    Sirena::Notation.register(
      FakeNotation::CountingPlugin.new(id: :fake, prefix: "FAKE",
                                       extensions: %w[.fake].freeze),
    )
  end

  # A fresh Ruby process: only the file named by --require can register.
  def run_cold(*)
    exe = File.expand_path("../../exe/sirena", __dir__)
    Open3.capture2(RbConfig.ruby, "-I", File.expand_path("..", __dir__), exe,
                   *)
  end

  def batch(*extra)
    run_cli("batch", "-i", File.join(dir, "in"), "-o", File.join(dir, "out"),
            *extra)
  end

  def outputs
    Dir.children(File.join(dir, "out")).sort
  end
end

RSpec.describe Sirena::Cli do
  include NotationCliHelpers

  include_context "with an isolated notation registry"

  let(:dir) { Dir.mktmpdir("sirena-notation-cli") }
  let(:flowchart) { "graph TD\nA-->B\n" }
  let(:fake) do
    FakeNotation::Plugin.new(id: :fake, extensions: %w[.fake].freeze,
                             prefix: "FAKE")
  end

  after { FileUtils.remove_entry(dir) }

  describe "render" do
    it "lets the file extension pick the notation" do
      register_unclaiming_fake
      out, = run_cli("render", write("x.fake"))

      expect(out).to include('data-notation="fake"')
    end

    it "gives stdin no path hint, so the source decides" do
      Sirena::Notation.register(fake)
      allow($stdin).to receive(:read).and_return("FAKE body")
      out, = run_cli("render", "-")

      expect(out).to include('data-notation="fake"')
    end

    it "lets --notation override the extension" do
      Sirena::Notation.register(fake)
      _, err, status = run_cli("render", "--notation", "fake", write("a.mmd"))

      expect([status, err]).to match([1, /Unable to detect diagram type/])
    end

    it "reports an unknown notation and exits 1" do
      _, err, status = run_cli("render", "--notation", "nope", write("a.mmd"))

      expect([status, err]).to eq(
        [1, "Error: Unknown notation: nope. Valid notations: mermaid\n"],
      )
    end

    it "reports a --require that cannot load and exits 1" do
      _, err, status = run_cli("render", "-r", "no_such_notation_file",
                               write("a.mmd"))

      expect([status, err])
        .to eq([1, "Error: Cannot load notation: no_such_notation_file\n"])
    end
  end

  describe "batch" do
    it "globs and renames extensions case-insensitively" do
      write("in/C.MMD")
      write("in/sub/d.mmd")
      write("in/skip.txt")
      batch

      expect(outputs).to eq(["C.svg", "sub"])
    end

    it "picks up another registered notation's extensions" do
      Sirena::Notation.register(fake)
      write("in/a.mmd")
      write("in/b.fake", "FAKE body")
      batch

      expect(outputs).to eq(%w[a.svg b.svg])
    end

    it "restricts the glob to --notation's extensions" do
      Sirena::Notation.register(fake)
      write("in/a.mmd")
      write("in/b.fake", "FAKE body")
      batch("--notation", "fake")

      expect(outputs).to eq(["b.svg"])
    end

    it "keeps the name of a single file whose extension is unregistered" do
      write("in/one.txt")
      run_cli("batch", "-i", File.join(dir, "in/one.txt"),
              "-o", File.join(dir, "out"))

      expect(outputs).to eq(["one.txt"])
    end
  end

  describe "types" do
    it "groups types under each notation id with a blank line between" do
      Sirena::Notation.register(fake)
      out, = run_cli("types")

      expect(out).to start_with("Supported diagram types:\n\nmermaid:\n  ")
        .and end_with("\n\nfake:\n  fake_box\n")
    end
  end

  describe "help" do
    it "says diagram, not Mermaid diagram, and lists the new options" do
      out, = run_cli("help", "render")

      expect([out.include?("Mermaid diagram"),
              out.include?("--notation"), out.include?("--require")])
        .to eq([false, true, true])
    end
  end

  describe "a cold subprocess" do
    let(:source_file) { write("x.fake", "FAKE body") }
    let(:plugin_file) do
      write("fake_notation_plugin.rb", <<~RUBY)
        require "support/fake_notation"
        Sirena::Notation.register(
          FakeNotation::Plugin.new(id: :fake, extensions: %w[.fake].freeze,
                                   prefix: "FAKE"),
        )
      RUBY
    end

    it "renders a notation loaded only through --require" do
      out, status = run_cold("render", "--require", plugin_file, source_file)

      expect([status.exitstatus, out]).to match([0, /data-notation="fake"/])
    end
  end
end
