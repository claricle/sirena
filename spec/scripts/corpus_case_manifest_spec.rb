# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../scripts/corpus_case_manifest"

module CorpusCaseManifestHelpers
  def pie_spec = "/packages/mermaid/src/diagrams/pie/pieDb.spec.ts"
  def checkout = "/Users/someone/src/mermaid-js"

  def write_case(dir, old_case, source:, title: nil, source_file: pie_spec)
    base = File.join(dir, old_case.delete_suffix(".mmd"))
    FileUtils.mkdir_p(File.dirname(base))
    File.write("#{base}.mmd", source)
    return if source_file == :omit

    meta = { name: "x", type: File.dirname(old_case), source_file: source_file,
             line_number: 1 }
    meta[:metadata] = { test_name: title } if title
    File.write("#{base}.meta.json", JSON.generate(meta))
  end

  def suppress_collision
    yield
  rescue CorpusCaseIdentity::CollisionError
    nil
  end

  def new_ids(manifest) = manifest["pairs"].to_h { [_1["old"], _1["new"]] }

  def manifest_for(cases)
    in_corpus { |dir| build_in(dir, cases) }
  end

  def build_in(dir, cases)
    cases.each { |name, opts| write_case(dir, name, **opts) }
    described_class.build(corpus_dir: dir)
  end

  def in_corpus(&)
    Dir.mktmpdir(&)
  end

  def pie_case(source, **opts) = { source: source, **opts }

  def clashing_pair
    { "pie/001_a.mmd" => pie_case("pie a\n"),
      "pie/002_b.mmd" => pie_case("pie b\n") }
  end

  def write_clashing(dir, out)
    clashing_pair.each { |name, opts| write_case(dir, name, **opts) }
    CorpusCaseManifest.write(corpus_dir: dir, path: out)
  end

  # Writes the manifest for `cases` into a fresh dir, yields dir and path.
  def with_written_manifest(cases)
    in_corpus do |dir|
      build_in(dir, cases)
      out = File.join(dir, "config", "manifest.json")
      described_class.write(corpus_dir: dir, path: out)
      yield dir, out
    end
  end
end

RSpec.describe CorpusCaseManifest do
  include CorpusCaseManifestHelpers

  let(:prefixed) { "#{checkout}#{pie_spec}" }
  let(:a) { pie_case("pie title A\n", title: "a") }
  let(:b) { pie_case("pie title B\n", title: "b") }
  let(:z) { pie_case("pie Z\n", title: "z") }
  let(:expected_id) do
    CorpusCaseIdentity.id_for(type: "pie", upstream_path: pie_spec,
                              title: "a", source: "pie title A\n")
  end

  it "maps an ordinal case to the id the identity module computes" do
    expect(new_ids(manifest_for("pie/001_a.mmd" => a)))
      .to eq("pie/001_a.mmd" => expected_id)
  end

  it "gives a relative and a checkout-prefixed source_file the same id" do
    prefixed_case = a.merge(source_file: prefixed)
    expect(new_ids(manifest_for("pie/001_a.mmd" => prefixed_case)).values)
      .to eq([expected_id])
  end

  it "keeps every new id when the ordinal numbers shift" do
    before = new_ids(manifest_for("pie/001_a.mmd" => a, "pie/002_b.mmd" => b))
    after = new_ids(manifest_for("pie/001_z.mmd" => z, "pie/002_a.mmd" => a,
                                 "pie/003_b.mmd" => b))
    expect(after.values).to include(*before.values)
  end

  it "lists a case without a meta file as unmapped" do
    manifest = manifest_for("pie/001_a.mmd" => a.merge(source_file: :omit))
    expect(manifest["unmapped"])
      .to eq([{ "case" => "pie/001_a.mmd", "reason" => "no .meta.json" }])
  end

  it "lists a case without a source_file as unmapped" do
    manifest = manifest_for("pie/001_a.mmd" => a.merge(source_file: ""))
    expect(manifest["unmapped"].map { _1["reason"] })
      .to eq(["meta has no source_file"])
  end

  it "invents no id for an unmapped case" do
    manifest = manifest_for("pie/001_a.mmd" => a.merge(source_file: :omit))
    expect(manifest["pairs"]).to be_empty
  end

  it "renders identical bytes on two runs" do
    cases = { "pie/001_a.mmd" => a, "pie/002_b.mmd" => b }
    runs = Array.new(2) { described_class.render(manifest_for(cases)) }
    expect(runs.uniq.length).to eq(1)
  end

  context "when two cases claim one id" do
    before do
      allow(CorpusCaseIdentity).to receive(:id_for)
        .and_return("pie/clash-00000000")
    end

    it "raises" do
      expect { manifest_for(clashing_pair) }
        .to raise_error(CorpusCaseIdentity::CollisionError)
    end

    it "writes no manifest file" do
      in_corpus do |dir|
        out = File.join(dir, "config", "manifest.json")
        suppress_collision { write_clashing(dir, out) }
        expect(File.exist?(out)).to be(false)
      end
    end
  end

  it "reports a manifest as fresh right after it is written" do
    with_written_manifest("pie/001_a.mmd" => a) do |dir, out|
      expect(described_class.stale?(corpus_dir: dir, path: out)).to be(false)
    end
  end

  it "reports a manifest as stale once the corpus gains a case" do
    with_written_manifest("pie/001_a.mmd" => a) do |dir, out|
      write_case(dir, "pie/002_b.mmd", source: "pie b\n")
      expect(described_class.stale?(corpus_dir: dir, path: out)).to be(true)
    end
  end

  it "has a committed manifest that matches the committed corpus" do
    expect(described_class.stale?).to be(false)
  end

  describe "duplicate directories of one diagram type" do
    def git_twin = pie_case("gitGraph\n  commit\n")

    def merged
      manifest_for("git/001_a_0.mmd" => git_twin,
                   "gitgraph/001_b_0.mmd" => git_twin,
                   "class/001_c_0.mmd" => a,
                   "class_diagram/001_d_0.mmd" => b)
    end

    [%w[class class_diagram], %w[er er_diagram], %w[git gitgraph],
     %w[gitgraph gitgraph], %w[state state_diagram],
     %w[state_diagram state_diagram], %w[unknown unknown],
     %w[pie pie], %w[nonesuch nonesuch]].each do |directory, canonical|
      it "sends #{directory}/ to #{canonical}/" do
        expect(described_class.canonical_directory(directory))
          .to eq(canonical)
      end
    end

    it "names the canonical directory in every new id" do
      expect(new_ids(merged).transform_values { _1.split("/").first })
        .to eq("git/001_a_0.mmd" => "gitgraph",
               "gitgraph/001_b_0.mmd" => "gitgraph",
               "class/001_c_0.mmd" => "class_diagram",
               "class_diagram/001_d_0.mmd" => "class_diagram")
    end

    it "keeps twins from the merged directories unique" do
      ids = new_ids(merged).values_at("git/001_a_0.mmd",
                                      "gitgraph/001_b_0.mmd")
      expect(ids.map { _1.split("/").last }.uniq.length).to eq(2)
    end

    it "gives identical ids on a second run" do
      cases = { "git/001_a_0.mmd" => git_twin,
                "gitgraph/001_b_0.mmd" => git_twin }
      runs = Array.new(2) { described_class.render(manifest_for(cases)) }
      expect(runs.uniq.length).to eq(1)
    end
  end
end
