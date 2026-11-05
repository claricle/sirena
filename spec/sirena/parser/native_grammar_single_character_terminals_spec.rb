# frozen_string_literal: true

require "spec_helper"

# The parsanol engine matches a single-character `%xNN` terminal with an
# unanchored regex search, so every attempt scans to the end of the input
# when the character does not occur later: parsing goes quadratic. A quoted
# string and a range such as `%x41-5A` match in place.
RSpec.describe Sirena::Parser::Native, ".grammar" do
  let(:grammar_glob) do
    File.expand_path("../../../native_grammar/*.parg", __dir__)
  end
  let(:terminal) { /(?<![0-9A-Fa-f.-])%x\h+(?:\.\h+)*(?![0-9A-Fa-f.-])/ }
  let(:quoted) { /"(?:\\.|[^"\\])*"/ }

  # Terminals outside quoted strings and comment lines.
  def single_terminals(text)
    code = text.each_line.reject { |line| line.lstrip.start_with?("#") }
    code.join.gsub(quoted, '""').scan(terminal)
  end

  it "finds a single-character terminal in a rule" do
    expect(single_terminals("r = %x5E \"x\"\ns = \"%x41\" %x41-5A\n"))
      .to eq(["%x5E"])
  end

  it "finds a concatenated terminal" do
    expect(single_terminals("newline = %x0D.0A\n")).to eq(["%x0D.0A"])
  end

  it "has no single-character %xNN terminal in any fragment" do
    offenders = Dir.glob(grammar_glob).to_h do |path|
      text = File.read(path, encoding: "UTF-8")
      [File.basename(path), single_terminals(text)]
    end

    expect(offenders.reject { |_, found| found.empty? }).to be_empty
  end
end
