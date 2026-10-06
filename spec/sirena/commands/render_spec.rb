# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "stringio"
require "open3"
require "rbconfig"
require "sirena/commands/render"

# Reads what a command wrote as the bytes a UTF-8 consumer would see.
module Utf8Bytes
  def utf8_bytes(bytes)
    bytes.dup.force_encoding(Encoding::UTF_8)
  end

  def japanese_text
    "\u65E5\u672C caf\u00e9"
  end

  def write_japanese_source(dir)
    File.join(dir, "ja.mmd").tap do |path|
      File.binwrite(path, "pie title #{japanese_text}\n  \"Dogs\" : 3\n")
    end
  end

  def render_to(out, path)
    Sirena::Commands::RenderCommand.new(path, format: "svg", output: out).run
  end

  def render_in_child(locale, path)
    exe = File.expand_path("../../../exe/sirena", __dir__)
    Open3.capture2(RbConfig.ruby, "-E#{locale}", exe, "render", path,
                   binmode: true).first
  end
end

RSpec.describe Sirena::Commands::RenderCommand do
  include DefaultExternalEncoding
  include Utf8Bytes

  let(:options) { { format: "svg" } }
  let(:dir) { Dir.mktmpdir("sirena-render") }
  let(:input_path) do
    File.join(dir, "in.mmd").tap { |path| File.write(path, "pie title Pets\n  \"Dogs\" : 3\n  \"Cats\" : 2\n") }
  end
  let(:run_command) do
    ->(file, opts) { described_class.new(file, opts).run }
  end

  after { FileUtils.remove_entry(dir) }

  describe "format validation" do
    it "refuses a format other than svg before reading any input" do
      command = described_class.new(File.join(dir, "absent.mmd"), format: "png")

      expect { command.run }
        .to raise_error(ArgumentError, /Unsupported format: png.*Only SVG/)
    end

    it "refuses a missing format" do
      expect { run_command.call(input_path, {}) }
        .to raise_error(ArgumentError, /Unsupported format: \./)
    end
  end

  describe "input" do
    it "reads the named file and prints the SVG to stdout" do
      expect { run_command.call(input_path, options) }
        .to output(/\A<svg.*<\/svg>\s*\z/m).to_stdout
    end

    %w[- nil].each do |name|
      it "reads stdin when the file is #{name}" do
        file = name == "nil" ? nil : name

        allow($stdin).to receive(:read).and_return(File.read(input_path))

        expect { run_command.call(file, options) }.to output(/<svg/).to_stdout
      end
    end

    it "reports a missing file by name" do
      missing = File.join(dir, "absent.mmd")

      expect { run_command.call(missing, options) }
        .to raise_error(ArgumentError, "File not found: #{missing}")
    end

    it "reports an unreadable file by name" do
      input_path
      allow(File).to receive(:binread).and_raise(Errno::EACCES)

      expect { run_command.call(input_path, options) }
        .to raise_error(ArgumentError, "Permission denied: #{input_path}")
    end
  end

  # mmdc reads its input as UTF-8 whatever the locale. Under a non-UTF-8
  # locale `File.read` and `$stdin.read` tag a UTF-8 file with the locale's
  # encoding, and `Source` would then transcode it from that encoding and
  # draw mojibake.
  describe "input under a non-UTF-8 locale" do
    let(:cafe) { "pie title caf\u00e9\n  \"Dogs\" : 3\n" }

    # The matcher's capture buffer is made before the locale changes, so it
    # stays UTF-8 and the regexp can be matched against it.
    %w[ISO-8859-1 EUC-JP Shift_JIS ISO-8859-1:UTF-8].each do |locale|
      context "with #{locale} as the locale" do
        it "reads a file as UTF-8" do
          path = File.join(dir, "cafe.mmd")
          File.binwrite(path, cafe)

          expect do
            with_default_external(locale) { run_command.call(path, options) }
          end.to output(/>caf\u00e9</).to_stdout
        end

        it "reads stdin as UTF-8" do
          expect do
            with_default_external(locale) do
              with_stdin(cafe) { run_command.call("-", options) }
            end
          end.to output(/>caf\u00e9</).to_stdout
        end
      end
    end
  end

  describe "output" do
    let(:output_path) { File.join(dir, "out.svg") }

    it "writes the SVG to the requested path and keeps stdout empty" do
      expect { run_command.call(input_path, options.merge(output: output_path)) }
        .not_to output.to_stdout

      expect(File.read(output_path)).to start_with("<svg")
    end

    it "announces the written path only when verbose" do
      expect do
        run_command.call(input_path, options.merge(output: output_path, verbose: true))
      end.to output(/SVG written to #{Regexp.escape(output_path)}/).to_stdout
    end

    it "writes the same bytes to a file as it prints to stdout" do
      run_command.call(input_path, options.merge(output: output_path))

      expect { run_command.call(input_path, options) }
        .to output("#{File.read(output_path)}\n").to_stdout
    end

    it "reports an unwritable output path by name" do
      input_path
      allow(File).to receive(:binwrite).and_raise(Errno::EACCES)

      expect { run_command.call(input_path, options.merge(output: output_path)) }
        .to raise_error(
          ArgumentError, "Permission denied writing to: #{output_path}"
        )
    end
  end

  # The SVG is UTF-8. A text-mode write transcodes it to the locale's
  # encoding (`ruby -E`), or raises on a character it lacks. Stdout runs in a
  # child process: the example needs a real stream with the locale's encoding.
  describe "output under a non-UTF-8 locale" do
    %w[ISO-8859-1:UTF-8 EUC-JP:UTF-8 ISO-8859-1].each do |locale|
      it "writes the file as UTF-8 bytes with #{locale} as the locale" do
        out = File.join(dir, "out.svg")
        source = write_japanese_source(dir)
        with_default_external(locale) { render_to(out, source) }

        expect(utf8_bytes(File.binread(out)))
          .to be_valid_encoding.and include(">#{japanese_text}<")
      end

      it "prints stdout as UTF-8 bytes with #{locale} as the locale" do
        printed = render_in_child(locale, write_japanese_source(dir))

        expect(utf8_bytes(printed))
          .to be_valid_encoding.and include(">#{japanese_text}<")
      end
    end
  end

  describe "theme" do
    let(:output_path) { File.join(dir, "out.svg") }

    it "passes the theme option through to the rendered output" do
      dark_path = File.join(dir, "dark.svg")
      run_command.call(input_path, options.merge(output: output_path))
      run_command.call(
        input_path, options.merge(output: dark_path, theme: "dark")
      )

      expect(File.read(dark_path)).not_to eq(File.read(output_path))
    end
  end
end
