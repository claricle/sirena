# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"
require "json"

CORPUS_SWEEP_ROOT = File.expand_path("../..", __dir__)

# scripts/corpus_sweep.rb is a program that sweeps on load, so it runs as a
# subprocess. Its `info` cases all render well-formed SVG, which makes the
# unpatched run the control: the only difference in the seeded run is that
# Engine#render returns SVG-shaped output that is not XML.
RSpec.describe "scripts/corpus_sweep.rb", :aggregate_failures, type: :task do
  let(:info_cases) do
    Dir.glob(
      File.join(CORPUS_SWEEP_ROOT, "spec", "mermaid", "info", "*.mmd"),
    ).size
  end
  let(:valid_info_cases) do
    path = File.join(CORPUS_SWEEP_ROOT, "scoreboard", "corpus.json")
    scoreboard = JSON.parse(File.read(path))
    scoreboard.count do |row|
      row["case"].start_with?("info/") && row["verdict"] == "valid"
    end
  end
  # `<img src=` opens a tag that never closes, the shape of the XSS corpus case.
  let(:malformed_svg) do
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">' \
      "<text>Alice<img src=</text></svg>"
  end

  # Returns [stdout, status]; stderr is not part of what is asserted.
  let(:sweep_info) do
    lambda do |prelude = nil|
      args = prelude ? ["-r", prelude] : []
      script = File.join(CORPUS_SWEEP_ROOT, "scripts", "corpus_sweep.rb")
      out, _err, status = Open3.capture3(RbConfig.ruby, *args, script,
                                         "--failing", "info",
                                         chdir: CORPUS_SWEEP_ROOT)
      [out, status]
    end
  end
  let(:valid_summary) do
    "against valid cases only: #{valid_info_cases}/#{valid_info_cases}"
  end

  it "has info cases to sweep" do
    expect(info_cases).to be_positive
  end

  it "passes every oracle-valid info case with well-formed SVG" do
    out, status = sweep_info.call
    result = [status.success?, out.include?(valid_summary),
              out.scan(%r{^fail: info/}).size]
    expect(result).to eq([true, true, info_cases - valid_info_cases])
  end

  it "reports a failure, not a pass, for SVG-shaped output that is not XML" do
    Dir.mktmpdir do |dir|
      prelude = File.join(dir, "seed_malformed.rb")
      File.write(prelude, <<~RUBY)
        require 'bundler/setup'
        $LOAD_PATH.unshift(#{File.join(CORPUS_SWEEP_ROOT, 'lib').inspect})
        require 'sirena'
        Sirena::Engine.prepend(Module.new { def render(*) = #{malformed_svg.inspect} })
      RUBY

      out, = sweep_info.call(prelude)

      expect(out).to include("TOTAL: 0/#{info_cases}")
      expect(out.scan(%r{^fail: info/}).size).to eq(info_cases)
    end
  end
end
