# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "stringio"
require_relative "../../scripts/extract_mermaid_tests"

# Refreshes a synthetic corpus from a synthetic mermaid-js checkout.
module CorpusRefreshHelpers
  def sha_one = "a" * 40
  def sha_two = "b" * 40
  def test_a = ["handles titles", "pie title A\n  \"x\" : 1"]
  def test_b = ["handles showData", "pie showData\n  \"y\" : 2"]
  def test_c = ["handles comments", "pie\n  %% note\n  \"z\" : 3"]

  def write_upstream(root, tests)
    path = File.join(root, "packages/mermaid/src/diagrams/pie/pieDb.spec.ts")
    FileUtils.mkdir_p(File.dirname(path))
    body = tests.map do |title, source|
      "  it('#{title}', () => {\n    parser.parse(`#{source}`);\n  });\n"
    end
    File.write(path, "describe('pie', () => {\n#{body.join}});\n")
  end

  def refresh(dir, **)
    real = $stdout
    $stdout = StringIO.new
    MermaidTestExtractor.new(root: "#{dir}/mermaid-js",
                             output_dir: "#{dir}/corpus", **)
      .extract_all
  ensure
    $stdout = real
  end

  # { relative path => bytes } for every file under dir.
  def snapshot(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir)
      .select { File.file?(File.join(dir, _1)) }
      .to_h { [_1, File.binread(File.join(dir, _1))] }
  end

  def leftovers(dir)
    Dir.children(dir).reject { %w[corpus mermaid-js].include?(_1) }
  end

  # Seeds upstream with `tests`, refreshes once, then yields the tmp dir.
  def seeded(tests, **options)
    Dir.mktmpdir do |dir|
      write_upstream("#{dir}/mermaid-js", tests)
      refresh(dir, commit_sha: sha_one, **options)
      yield dir
    end
  end

  def shas(dir)
    Dir.glob("#{dir}/corpus/*/*.meta.json")
      .map { JSON.parse(File.read(_1))["upstream_sha"] }
  end

  # Upstream loses test_b after the corpus was built; returns the outcome.
  def refresh_after(dir, tests, **)
    write_upstream("#{dir}/mermaid-js", tests)
    outcome_of { refresh(dir, commit_sha: sha_one, **) }
  end

  def add_sidecars(dir)
    mmd = Dir.glob("#{dir}/corpus/pie/*.mmd").first
    %w[.svg .error].each { File.write(mmd.sub(".mmd", _1), "x") }
  end

  def refresh_with_failing_swap(dir)
    fail_swap
    refresh(dir, commit_sha: sha_one)
  rescue SystemCallError
    nil
  end

  def fail_swap
    allow(File).to receive(:rename).and_wrap_original do |orig, from, to|
      raise Errno::EACCES, to if from.include?(".staging-")

      orig.call(from, to)
    end
  end

  def outcome_of
    yield
    nil
  rescue CorpusRefresh::Error => e
    e
  end
end

RSpec.describe CorpusRefresh do
  include CorpusRefreshHelpers

  it "gives a zero diff when the same tree is extracted twice" do
    seeded([test_a, test_b]) do |dir|
      before = snapshot("#{dir}/corpus")
      refresh(dir, commit_sha: sha_one)
      expect(snapshot("#{dir}/corpus")).to eq(before)
    end
  end

  it "leaves no staging or backup directory behind" do
    seeded([test_a]) do |dir|
      refresh(dir, commit_sha: sha_one)
      expect(leftovers(dir)).to be_empty
    end
  end

  it "writes the commit sha into every meta file" do
    seeded([test_a, test_b]) { |dir| expect(shas(dir)).to eq([sha_one] * 2) }
  end

  it "changes only the sha when the checkout moves and content is equal" do
    seeded([test_a]) do |dir|
      refresh(dir, commit_sha: sha_two)
      expect(shas(dir)).to eq([sha_two])
    end
  end

  it "aborts a refresh that loses a case" do
    seeded([test_a, test_b]) do |dir|
      expect(refresh_after(dir, [test_a])).to be_a(CorpusRefresh::LossyError)
    end
  end

  it "leaves the old tree untouched when a refresh loses a case" do
    seeded([test_a, test_b]) do |dir|
      before = snapshot("#{dir}/corpus")
      refresh_after(dir, [test_a])
      expect(snapshot("#{dir}/corpus")).to eq(before)
    end
  end

  it "leaves no staging directory behind after an abort" do
    seeded([test_a, test_b]) do |dir|
      refresh_after(dir, [test_a])
      expect(leftovers(dir)).to be_empty
    end
  end

  it "aborts when the count is equal but a source changed" do
    seeded([test_a, test_b]) do |dir|
      edited = [test_b.first, "#{test_b.last}\n  \"w\" : 3"]
      expect(refresh_after(dir, [test_a, edited]))
        .to be_a(CorpusRefresh::LossyError)
    end
  end

  it "aborts when one of two identical tests disappears" do
    seeded([test_a, test_a]) do |dir|
      expect(refresh_after(dir, [test_a])).to be_a(CorpusRefresh::LossyError)
    end
  end

  it "applies a changed corpus when changes are accepted" do
    seeded([test_a, test_b]) do |dir|
      refresh_after(dir, [test_a], accept_changes: true)
      expect(Dir.glob("#{dir}/corpus/*/*.mmd").length).to eq(1)
    end
  end

  it "drops svg and error sidecars, which the oracle owns" do
    seeded([test_a]) do |dir|
      add_sidecars(dir)
      refresh(dir, commit_sha: sha_one)
      expect(Dir.glob("#{dir}/corpus/pie/*").grep(/\.(svg|error)\z/)).to eq([])
    end
  end

  it "carries top-level files such as verdict tables across" do
    seeded([test_a]) do |dir|
      File.write("#{dir}/corpus/oracle-verdicts.yml", "--- []\n")
      refresh(dir, commit_sha: sha_one)
      expect(File.read("#{dir}/corpus/oracle-verdicts.yml")).to eq("--- []\n")
    end
  end

  it "raises when the swap fails" do
    seeded([test_a]) do |dir|
      fail_swap
      expect { refresh(dir, commit_sha: sha_one) }
        .to raise_error(SystemCallError)
    end
  end

  it "restores the old tree when the swap fails" do
    seeded([test_a]) do |dir|
      before = snapshot("#{dir}/corpus")
      refresh_with_failing_swap(dir)
      expect(snapshot("#{dir}/corpus")).to eq(before)
    end
  end

  it "rejects a commit sha that is not 40 hex characters" do
    expect do
      MermaidTestExtractor.new(root: "/tmp/mermaid-js", commit_sha: "main")
    end
      .to raise_error(CorpusRefresh::Error, /40 hex/)
  end

  it "extracts a first corpus without a previous tree to compare" do
    Dir.mktmpdir do |dir|
      write_upstream("#{dir}/mermaid-js", [test_a])
      refresh(dir, commit_sha: sha_one)
      expect(Dir.glob("#{dir}/corpus/pie/*.mmd").length).to eq(1)
    end
  end
end
