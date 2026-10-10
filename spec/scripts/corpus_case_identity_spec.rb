# frozen_string_literal: true

require "spec_helper"
require_relative "../../scripts/corpus_case_identity"

# Synthetic upstream: a hash of path => [[title, source], ...] in the order
# the tests appear in that file.
module CorpusCaseIdentityHelpers
  def upstream_path = "packages/mermaid/src/diagrams/pie/pieDb.spec.ts"
  def first_test = ["handles titles", "pie title A\n  \"x\" : 1"]
  def second_test = ["handles showData", "pie showData\n  \"y\" : 2"]
  def third_test = ["handles comments", "pie\n  %% note\n  \"z\" : 3"]
  def inserted_test = ["handles a new thing", "pie title New\n  \"n\" : 9"]
  def pie_source = "pie title Pets\n  \"Dogs\" : 386"
  def graph_source = "graph TD\n  A --> B"

  def records_from(upstream, type: "pie")
    upstream.flat_map do |path, tests|
      tests.map do |title, source|
        { type: type, upstream_path: path, title: title, source: source }
      end
    end
  end

  def ids_of(records)
    described_class.assign_ids(records).map { |record| record[:id] }
  end

  def ids_by_test(tests, path: upstream_path)
    ids = ids_of(records_from({ path => tests }))
    tests.zip(ids).to_h
  end

  def id_for_record(**changes)
    base = { type: "pie", upstream_path: upstream_path,
             title: "handles titles", source: "pie" }
    described_class.id_for(base.merge(changes))
  end

  def hash_of(id) = id[/\h{8}\z/]
  def stem_of(id) = id.sub(/-\h{8}\z/, "")

  def with_occurrence_zero(records)
    records.map { |record| record.merge(occurrence: 0) }
  end
end

RSpec.describe CorpusCaseIdentity do
  include CorpusCaseIdentityHelpers

  # The same scenarios for titled tests and for untitled blocks, so
  # identity is proven on both branches of the identity string.
  {
    "titled" => ->(test) { test },
    "untitled" => ->(test) { [nil, test[1]] },
  }.each do |label, shape|
    context "with #{label} tests" do
      let(:tests) { [first_test, second_test, third_test].map(&shape) }
      let(:before_ids) { ids_by_test(tests) }

      it "keeps every ID when a test is inserted before another" do
        grown = [tests[0], shape.call(inserted_test), *tests[1..]]

        expect(ids_by_test(grown)).to include(before_ids)
      end

      it "gives the inserted test an ID of its own" do
        grown = [tests[0], shape.call(inserted_test), *tests[1..]]

        expect(ids_by_test(grown).values.uniq.length).to eq(4)
      end

      it "keeps every ID when two tests are reordered" do
        reordered = [tests[0], tests[2], tests[1]]

        expect(ids_by_test(reordered)).to eq(before_ids)
      end

      it "keeps the surviving IDs when a test is deleted" do
        survivors = [tests[0], tests[2]]

        expect(ids_by_test(survivors)).to eq(before_ids.slice(*survivors))
      end
    end
  end

  describe ".id_for" do
    it "has the shape <type>/<slug>-<hash8>" do
      expect(id_for_record).to match(%r{\Apie/handles_titles-\h{8}\z})
    end

    it "changes when the source changes" do
      expect(hash_of(id_for_record(source: "pie showData")))
        .not_to eq(hash_of(id_for_record))
    end

    it "leaves the slug alone when only the source changes" do
      expect(stem_of(id_for_record(source: "pie showData")))
        .to eq(stem_of(id_for_record))
    end

    it "changes when the upstream path changes" do
      moved = id_for_record(upstream_path: "cypress/rendering/pie.spec.ts")

      expect(moved).not_to eq(id_for_record)
    end

    it "changes when the test title changes" do
      expect(id_for_record(title: "handles more")).not_to eq(id_for_record)
    end

    it "ignores line endings, trailing blanks and a leading slash" do
      messy = id_for_record(source: "pie  \r\n\r\n",
                            upstream_path: "/#{upstream_path}")

      expect(messy).to eq(id_for_record)
    end

    it "slugs the last title of a describe/it path" do
      nested = id_for_record(title: ["pie diagram", "handles titles"])

      expect(stem_of(nested)).to eq("pie/handles_titles")
    end

    it "hashes every title of a describe/it path" do
      nested = id_for_record(title: ["pie diagram", "handles titles"])

      expect(hash_of(nested)).not_to eq(hash_of(id_for_record))
    end

    {
      "a missing type" => { type: nil },
      "a type that could leave its directory" => { type: "../pie" },
      "an empty upstream path" => { upstream_path: "/" },
      "a NUL in the path" => { upstream_path: "a\0b.ts" },
      "a NUL in the title" => { title: "a\0b" },
      "a source that is not UTF-8" => { source: "pie \xFF".b },
    }.each do |label, change|
      it "rejects #{label}" do
        expect { id_for_record(**change) }
          .to raise_error(CorpusCaseIdentity::InvalidRecordError)
      end
    end
  end

  describe "slug safety" do
    {
      "path separators" => "../../etc/passwd",
      "punctuation" => "should handle: 'quotes', \"double\" & <angles>!",
      "non-ASCII" => "gestión de ñandú — 日本語",
      "shell metacharacters" => "$(rm -rf ~); `id` | cat > /dev/null",
      "a Windows reserved name" => "CON",
      "only symbols" => "!!!???",
      "an enormous title" => "very long title " * 40,
    }.each do |label, title|
      it "keeps #{label} to filesystem-safe characters" do
        expect(id_for_record(title: title))
          .to match(%r{\Apie/[a-z0-9_]{1,48}-\h{8}\z})
      end
    end

    it "is accepted by the corpus case-path shape" do
      id = id_for_record(title: "Handles: titles")

      expect("#{id}.mmd").to match(%r{\A[a-z0-9_]+/[A-Za-z0-9_.-]+\.mmd\z})
    end
  end

  describe ".assign_ids" do
    let(:twins) { records_from({ upstream_path => [[nil, pie_source]] * 2 }) }

    it "gives identical twins in one file distinct IDs" do
      expect(ids_of(twins).uniq.length).to eq(2)
    end

    it "keeps a twin's ID when an unrelated test is inserted before it" do
      shifted = records_from(
        { upstream_path => [[nil, graph_source], *[[nil, pie_source]] * 2] },
      )

      expect(ids_of(shifted).drop(1)).to eq(ids_of(twins))
    end

    it "raises when two cases claim one ID" do
      expect { described_class.assign_ids(with_occurrence_zero(twins)) }
        .to raise_error(CorpusCaseIdentity::CollisionError,
                        %r{2 cases claim pie/piedb_spec-})
    end

    it "raises when two different tests hash to the same ID" do
      allow(described_class).to receive(:digest8).and_return("deadbeef")
      different = records_from({ upstream_path => [["t", "a"], ["t", "b"]] })

      expect { described_class.assign_ids(different) }
        .to raise_error(CorpusCaseIdentity::CollisionError, /-deadbeef/)
    end
  end

  describe ".migration_manifest" do
    let(:old_records) do
      tests = [first_test, second_test, third_test]
      records_from({ upstream_path => tests }).each_with_index.map do |r, i|
        r.merge(case: format("pie/%<n>03d_old.mmd", n: i + 1))
      end
    end

    def manifest_for(tests, old: old_records)
      build_manifest(old, records_from({ upstream_path => tests }))
    end

    def build_manifest(old, new)
      described_class.migration_manifest(old_records: old, new_records: new)
    end

    it "pairs each old ordinal case with the ID of the same block" do
      expected = old_records.zip(ids_of(old_records)).map do |old, id|
        { old: old[:case], new: id }
      end
      reordered = manifest_for([third_test, first_test, second_test])

      expect(reordered[:pairs]).to eq(expected.sort_by { _1[:old] })
    end

    it "reports nothing lost or gained when the upstream is reordered" do
      reordered = manifest_for([third_test, first_test, second_test])

      expect(reordered.values_at(:deletions, :additions)).to eq([[], []])
    end

    it "lists a vanished upstream test as a deletion" do
      pruned = manifest_for([first_test, third_test])

      expect(pruned[:deletions]).to eq([old_records[1][:case]])
    end

    it "still pairs the surviving cases after a deletion" do
      pruned = manifest_for([first_test, third_test])

      expect(pruned[:pairs].map { _1[:old] })
        .to eq([old_records[0][:case], old_records[2][:case]])
    end

    it "lists a new upstream test as an addition" do
      grown = manifest_for(
        [first_test, inserted_test, second_test, third_test],
      )

      expect(grown[:additions])
        .to eq([ids_by_test([inserted_test]).fetch(inserted_test)])
    end

    it "treats a test whose source changed as a deletion plus an addition" do
      edited = [second_test[0], "#{second_test[1]}\n  \"extra\" : 4"]
      changed = manifest_for([first_test, edited, third_test])

      expect(changed.values_at(:deletions, :additions).map(&:length))
        .to eq([1, 1])
    end

    it "raises when the new records collide" do
      claimed = with_occurrence_zero(
        records_from({ upstream_path => [["t", pie_source]] * 2 }),
      )

      expect { build_manifest([], claimed) }
        .to raise_error(CorpusCaseIdentity::CollisionError)
    end

    it "raises when the old records collide" do
      collided = old_records.map do |r|
        r.merge(occurrence: 0, title: "t", source: pie_source)
      end

      expect { manifest_for([], old: collided) }
        .to raise_error(CorpusCaseIdentity::CollisionError)
    end

    it "raises when one old case is listed twice" do
      repeated = old_records.map { |r| r.merge(case: "pie/001_same.mmd") }

      expect { manifest_for([], old: repeated) }
        .to raise_error(CorpusCaseIdentity::InvalidRecordError, /twice/)
    end
  end
end
