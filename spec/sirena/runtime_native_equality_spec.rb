# frozen_string_literal: true

require "spec_helper"
require_relative "../support/native_equality"

# Runs only where `sirena-native` is installed and finds its shared library
# (the CI job `native-runtime`, or a local build via SIRENA_NATIVE_LIB). It
# proves the Rust runtime and the Ruby pipeline write the same SVG bytes for
# the Mermaid corpus, one example per diagram type. Elsewhere it is skipped
# and the Ruby path is the one the rest of the suite covers.
RSpec.describe Sirena::Runtime do
  skipped = described_class.native? ? false : "sirena-native not loadable"

  it "loads the native runtime when SIRENA_RUNTIME=rust demands it",
     skip: (ENV["SIRENA_RUNTIME"] == "rust" ? false : "not demanded") do
    expect(described_class).to be_native
  end

  NativeEquality.paths_by_type.each do |type, paths|
    it "renders #{type} identically through Rust and Ruby", skip: skipped do
      tally = NativeEquality.compare(paths)
      warn "native #{type}: #{tally[:same]} same, " \
           "#{tally[:unported].size} unported"

      expect(tally[:different]).to eq([])
    end
  end
end
