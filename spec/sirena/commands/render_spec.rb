# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'stringio'
require 'sirena/commands/render'

RSpec.describe Sirena::Commands::RenderCommand do
  include DefaultExternalEncoding

  let(:options) { { format: 'svg' } }
  let(:dir) { Dir.mktmpdir('sirena-render') }
  let(:input_path) do
    File.join(dir, 'in.mmd').tap { |path| File.write(path, "pie title Pets\n  \"Dogs\" : 3\n  \"Cats\" : 2\n") }
  end
  let(:run_command) do
    ->(file, opts) { described_class.new(file, opts).run }
  end

  after { FileUtils.remove_entry(dir) }

  describe 'format validation' do
    it 'refuses a format other than svg before reading any input' do
      command = described_class.new(File.join(dir, 'absent.mmd'), format: 'png')

      expect { command.run }
        .to raise_error(ArgumentError, /Unsupported format: png.*Only SVG/)
    end

    it 'refuses a missing format' do
      expect { run_command.call(input_path, {}) }
        .to raise_error(ArgumentError, /Unsupported format: \./)
    end
  end

  describe 'input' do
    it 'reads the named file and prints the SVG to stdout' do
      expect { run_command.call(input_path, options) }
        .to output(/\A<svg.*<\/svg>\s*\z/m).to_stdout
    end

    %w[- nil].each do |name|
      it "reads stdin when the file is #{name}" do
        file = name == 'nil' ? nil : name

        allow($stdin).to receive(:read).and_return(File.read(input_path))

        expect { run_command.call(file, options) }.to output(/<svg/).to_stdout
      end
    end

    it 'reports a missing file by name' do
      missing = File.join(dir, 'absent.mmd')

      expect { run_command.call(missing, options) }
        .to raise_error(ArgumentError, "File not found: #{missing}")
    end

    it 'reports an unreadable file by name' do
      input_path
      allow(File).to receive(:read).and_raise(Errno::EACCES)

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
    %w[ISO-8859-1 EUC-JP Shift_JIS].each do |locale|
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

  describe 'output' do
    let(:output_path) { File.join(dir, 'out.svg') }

    it 'writes the SVG to the requested path and keeps stdout empty' do
      expect { run_command.call(input_path, options.merge(output: output_path)) }
        .not_to output.to_stdout

      expect(File.read(output_path)).to start_with('<svg')
    end

    it 'announces the written path only when verbose' do
      expect do
        run_command.call(input_path, options.merge(output: output_path, verbose: true))
      end.to output(/SVG written to #{Regexp.escape(output_path)}/).to_stdout
    end

    it 'writes the same bytes to a file as it prints to stdout' do
      run_command.call(input_path, options.merge(output: output_path))

      expect { run_command.call(input_path, options) }
        .to output("#{File.read(output_path)}\n").to_stdout
    end

    it 'reports an unwritable output path by name' do
      input_path
      allow(File).to receive(:write).and_raise(Errno::EACCES)

      expect { run_command.call(input_path, options.merge(output: output_path)) }
        .to raise_error(
          ArgumentError, "Permission denied writing to: #{output_path}"
        )
    end
  end

  describe 'theme' do
    let(:output_path) { File.join(dir, 'out.svg') }

    it 'passes the theme option through to the rendered output' do
      dark_path = File.join(dir, 'dark.svg')
      run_command.call(input_path, options.merge(output: output_path))
      run_command.call(
        input_path, options.merge(output: dark_path, theme: 'dark')
      )

      expect(File.read(dark_path)).not_to eq(File.read(output_path))
    end
  end
end
