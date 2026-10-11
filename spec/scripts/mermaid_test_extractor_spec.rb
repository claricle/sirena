# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "stringio"
require_relative "../../scripts/extract_mermaid_tests"

# A synthetic mermaid-js checkout holding one upstream spec file. Each test
# is [title, pie source], written in file order.
module ExtractMermaidTestsHelpers
  UPSTREAM_FILE = "packages/mermaid/src/diagrams/pie/pieDb.spec.ts"

  def tests_a = ["handles titles", "pie title A\n  \"x\" : 1"]
  def tests_b = ["handles showData", "pie showData\n  \"y\" : 2"]
  def tests_c = ["handles comments", "pie\n  %% note\n  \"z\" : 3"]
  def tests_new = ["handles a new thing", "pie title New\n  \"n\" : 9"]

  def write_upstream(root, tests)
    path = File.join(root, UPSTREAM_FILE)
    FileUtils.mkdir_p(File.dirname(path))
    body = tests.map do |title, source|
      "  it('#{title}', () => {\n    parser.parse(`#{source}`);\n  });\n"
    end
    File.write(path, "describe('pie', () => {\n#{body.join}});\n")
  end

  def run_extractor(root, out, naming: :stable)
    real = $stdout
    $stdout = StringIO.new
    MermaidTestExtractor.new(root: root, output_dir: out, naming: naming)
      .extract_all
  ensure
    $stdout = real
  end

  # { test title => case id } read back from the written meta files.
  def ids_by_title(out)
    Dir.glob("#{out}/*/*.meta.json").to_h do |file|
      meta = JSON.parse(File.read(file))
      [meta.dig("metadata", "test_name"), meta.fetch("case_id")]
    end
  end

  # Runs a stable extraction in which every case claims one id.
  # Returns [error raised or nil, whether the output dir exists].
  def clashing_extraction(naming)
    Dir.mktmpdir do |dir|
      write_upstream("#{dir}/mermaid-js", [tests_a, tests_b])
      allow(CorpusCaseIdentity).to receive(:id_for)
        .and_return("pie/clash-00000000")
      error = begin
        run_extractor("#{dir}/mermaid-js", "#{dir}/out", naming: naming)
      rescue CorpusCaseIdentity::CollisionError => e
        e
      end
      [error, Dir.exist?("#{dir}/out")]
    end
  end

  def ordinal_output(tests)
    Dir.mktmpdir do |dir|
      write_upstream("#{dir}/mermaid-js", tests)
      run_extractor("#{dir}/mermaid-js", "#{dir}/out", naming: :ordinal)
      Dir.glob("#{dir}/out/pie/*").map { File.basename(_1) }.sort
    end
  end

  def ordinal_meta(tests)
    Dir.mktmpdir do |dir|
      write_upstream("#{dir}/mermaid-js", tests)
      run_extractor("#{dir}/mermaid-js", "#{dir}/out", naming: :ordinal)
      JSON.parse(File.read(Dir.glob("#{dir}/out/pie/*.json")[0]))
    end
  end

  def extract_ids(tests)
    Dir.mktmpdir do |dir|
      write_upstream("#{dir}/mermaid-js", tests)
      run_extractor("#{dir}/mermaid-js", "#{dir}/out")
      ids_by_title("#{dir}/out")
    end
  end
end

RSpec.describe MermaidTestExtractor do
  include ExtractMermaidTestsHelpers

  let(:base) { [tests_a, tests_b, tests_c] }
  let(:base_ids) { extract_ids(base) }
  let(:titles) { base.map(&:first) }

  it "extracts one stable id per seeded upstream test" do
    expect(base_ids.keys).to match_array(titles)
  end

  it "keeps every other id when an upstream test is inserted" do
    after = extract_ids([tests_a, tests_new, tests_b, tests_c])
    expect(after.slice(*titles)).to eq(base_ids)
  end

  it "gives an inserted upstream test an id of its own" do
    after = extract_ids([tests_a, tests_new, tests_b, tests_c])
    expect(after.values_at(*titles, tests_new.first).uniq.length).to eq(4)
  end

  it "keeps every id when upstream tests are reordered" do
    expect(extract_ids([tests_c, tests_a, tests_b])).to eq(base_ids)
  end

  it "keeps every other id when an upstream test is deleted" do
    expect(extract_ids([tests_a, tests_c]))
      .to eq(base_ids.except(tests_b.first))
  end

  it "changes only the edited test's id when its source changes" do
    edited = [tests_a, [tests_b.first, "#{tests_b.last}\n  \"w\" : 7"], tests_c]
    changed = extract_ids(edited).reject { |t, id| id == base_ids[t] }
    expect(changed.keys).to eq([tests_b.first])
  end

  it "raises on a seeded id collision" do
    expect(clashing_extraction(:stable).first)
      .to be_a(CorpusCaseIdentity::CollisionError)
  end

  it "writes nothing on a seeded id collision" do
    expect(clashing_extraction(:stable).last).to be(false)
  end

  it "raises on a seeded id collision in ordinal naming too" do
    expect(clashing_extraction(:ordinal).first)
      .to be_a(CorpusCaseIdentity::CollisionError)
  end

  it "keeps NNN_ file names under the default ordinal naming" do
    names = ordinal_output([tests_a, tests_b]).grep(/\.mmd\z/)
    expect(names.map { _1[/\A\d{3}_/] }).to eq(%w[001_ 002_])
  end

  it "adds no case_id to the meta under ordinal naming" do
    expect(ordinal_meta([tests_a])).not_to include("case_id")
  end

  it "rejects an unknown naming" do
    expect { described_class.new(naming: :random) }
      .to raise_error(ArgumentError, /naming must be one of/)
  end
end
