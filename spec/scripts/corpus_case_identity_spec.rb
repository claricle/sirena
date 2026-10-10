# frozen_string_literal: true

require "spec_helper"
require_relative "../../scripts/corpus_case_identity"

# Builds corpus records from a synthetic upstream: a hash of
# path => [[title, source], ...] in the order the tests appear in that file.
module CorpusCaseIdentityHelpers
  def path = "packages/mermaid/src/diagrams/pie/pieDb.spec.ts"
  def first = ["handles titles", "pie title A\n  \"x\" : 1"]
  def second = ["handles showData", "pie showData\n  \"y\" : 2"]
  def third = ["handles comments", "pie\n  %% note\n  \"z\" : 3"]
  def inserted = ["handles a new thing", "pie title New\n  \"n\" : 9"]
  def pie_source = "pie title Pets\n  \"Dogs\" : 386"
  def graph_source = "graph TD\n  A --> B"

  def records_from(upstream, type: "pie")
    upstream.flat_map do |path, tests|
      tests.map do |title, source|
        { type: type, upstream_path: path, title: title, source: source }
      end
    end
  end

  def ids_by_label(upstream, type: "pie")
    ids = described_class.assign_ids(records_from(upstream, type: type))
    ids.to_h { |record| [[record[:upstream_path], record[:title], record[:source]], record[:id]] }
  end

  def id_of(upstream, path, test)
    ids_by_label(upstream).fetch([path, test[0], test[1]])
  end
end

RSpec.describe CorpusCaseIdentity do
  include CorpusCaseIdentityHelpers

  # Same three scenarios, once with titled tests and once with untitled
  # blocks, so identity is proven for both branches of the identity string.
  [
    ["titled", ->(test) { test }],
    ["untitled", ->(test) { [nil, test[1]] }],
  ].each do |label, shape|
    context "with #{label} tests" do
      let(:tests) { [first, second, third].map(&shape) }
      let(:before_ids) { ids_by_label({ path => tests }) }

      it "keeps every ID when an upstream test is inserted before another" do
        after = ids_by_label({ path => [tests[0], shape.call(inserted), *tests[1..]] })

        expect(after.slice(*before_ids.keys)).to eq(before_ids)
        expect(after.values.uniq.length).to eq(4)
      end

      it "keeps every ID when two upstream tests are reordered" do
        after = ids_by_label({ path => [tests[0], tests[2], tests[1]] })

        expect(after).to eq(before_ids)
      end

      it "keeps the surviving IDs when an upstream test is deleted" do
        after = ids_by_label({ path => [tests[0], tests[2]] })

        expect(after).to eq(before_ids.slice(tests[0].then { |t| [path, *t] }, [path, *tests[2]]))
      end
    end
  end

  describe ".id_for" do
    let(:record) { { type: "pie", upstream_path: path, title: "handles titles", source: "pie\n" } }

    it "has the shape <type>/<slug>-<hash8>" do
      expect(described_class.id_for(record)).to match(%r{\Apie/handles_titles-\h{8}\z})
    end

    it "changes when the source changes" do
      changed = record.merge(source: "pie\n  \"Dogs\" : 1")

      expect(described_class.id_for(changed)).not_to eq(described_class.id_for(record))
    end

    it "changes only the hash when the source changes" do
      changed = record.merge(source: "pie showData")
      prefix = ->(id) { id.sub(/-\h{8}\z/, "") }

      expect(prefix.call(described_class.id_for(changed))).to eq(prefix.call(described_class.id_for(record)))
    end

    it "changes when the upstream path changes" do
      moved = record.merge(upstream_path: "cypress/integration/rendering/pie.spec.ts")

      expect(described_class.id_for(moved)).not_to eq(described_class.id_for(record))
    end

    it "changes when the test title changes" do
      renamed = record.merge(title: "handles other things")

      expect(described_class.id_for(renamed)).not_to eq(described_class.id_for(record))
    end

    it "ignores line endings, trailing blanks and a leading slash on the path" do
      messy = record.merge(source: "pie\r\n\r\n", upstream_path: "/#{path}")
      clean = record.merge(source: "pie")

      expect(described_class.id_for(messy)).to eq(described_class.id_for(clean))
    end

    it "uses the last title of a describe/it path for the slug and all of them for the hash" do
      nested = record.merge(title: ["pie diagram", "handles titles"])

      expect(described_class.id_for(nested)).to start_with("pie/handles_titles-")
      expect(described_class.id_for(nested)).not_to eq(described_class.id_for(record))
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
        expect { described_class.id_for(record.merge(change)) }
          .to raise_error(CorpusCaseIdentity::InvalidRecordError)
      end
    end
  end

  describe "slug safety" do
    {
      "path separators" => "../../etc/passwd",
      "spaces and punctuation" => "should handle: 'quotes', \"double\" & <angles>!",
      "non-ASCII" => "gestión de ñandú — 日本語",
      "shell metacharacters" => "$(rm -rf ~); `id` | cat > /dev/null",
      "a Windows reserved name" => "CON",
      "only symbols" => "!!!???",
      "an enormous title" => "very long title " * 40,
    }.each do |label, title|
      it "keeps #{label} to filesystem-safe characters" do
        id = described_class.id_for(type: "pie", upstream_path: path, title: title, source: "pie")

        expect(id).to match(%r{\Apie/[a-z0-9_]{1,48}-\h{8}\z})
      end
    end

    it "is accepted by the corpus case-path shape" do
      id = described_class.id_for(type: "pie", upstream_path: path, title: "Handles: titles", source: "pie")

      expect("#{id}.mmd").to match(%r{\A[a-z0-9_]+/[A-Za-z0-9_.-]+\.mmd\z})
    end
  end

  describe ".assign_ids" do
    it "gives identical twins in one file distinct, order-stable IDs" do
      twins = records_from({ path => [[nil, pie_source], [nil, pie_source]] })
      ids = described_class.assign_ids(twins).map { |r| r[:id] }

      expect(ids.uniq.length).to eq(2)
    end

    it "keeps a twin's ID when an unrelated test is inserted before it" do
      twins = records_from({ path => [[nil, pie_source], [nil, pie_source]] })
      shifted = records_from({ path => [[nil, graph_source], [nil, pie_source], [nil, pie_source]] })

      before = described_class.assign_ids(twins).map { |r| r[:id] }
      after = described_class.assign_ids(shifted).map { |r| r[:id] }

      expect(after.drop(1)).to eq(before)
    end

    it "raises when two cases claim one ID" do
      claimed = records_from({ path => [["t", pie_source], ["t", pie_source]] })
      claimed.each { |record| record[:occurrence] = 0 }

      expect { described_class.assign_ids(claimed) }
        .to raise_error(CorpusCaseIdentity::CollisionError, /2 cases claim pie\/t-/)
    end

    it "raises when two different tests hash to the same ID" do
      allow(described_class).to receive(:digest8).and_return("deadbeef")
      different = records_from({ path => [["t", pie_source], ["t", "pie showData"]] })

      expect { described_class.assign_ids(different) }
        .to raise_error(CorpusCaseIdentity::CollisionError, /pie\/t-deadbeef/)
    end
  end

  describe ".migration_manifest" do
    let(:old_records) do
      records_from({ path => [first, second, third] }).each_with_index.map do |record, index|
        record.merge(case: format("pie/%<n>03d_old_%<i>d.mmd", n: index + 1, i: index))
      end
    end

    it "pairs each old ordinal case with the ID of the same upstream block" do
      reordered = records_from({ path => [third, first, second] })
      manifest = described_class.migration_manifest(old_records: old_records, new_records: reordered)

      expected = old_records.zip(described_class.assign_ids(old_records)).map do |old, identified|
        { old: old[:case], new: identified[:id] }
      end
      expect(manifest[:pairs]).to eq(expected.sort_by { |pair| pair[:old] })
      expect(manifest.values_at(:deletions, :additions)).to eq([[], []])
    end

    it "lists a vanished upstream test as a deletion instead of dropping it" do
      manifest = described_class.migration_manifest(
        old_records: old_records, new_records: records_from({ path => [first, third] }),
      )

      expect(manifest[:deletions]).to eq([old_records[1][:case]])
      expect(manifest[:pairs].map { |pair| pair[:old] })
        .to eq([old_records[0][:case], old_records[2][:case]])
    end

    it "lists a new upstream test as an addition" do
      manifest = described_class.migration_manifest(
        old_records: old_records, new_records: records_from({ path => [first, inserted, second, third] }),
      )

      expect(manifest[:additions]).to eq([id_of({ path => [inserted] }, path, inserted)])
    end

    it "treats a test whose source changed as a deletion plus an addition" do
      edited = [second[0], "#{second[1]}\n  \"extra\" : 4"]
      manifest = described_class.migration_manifest(
        old_records: old_records, new_records: records_from({ path => [first, edited, third] }),
      )

      expect([manifest[:deletions].length, manifest[:additions].length]).to eq([1, 1])
    end

    it "raises when the new records collide" do
      collided = records_from({ path => [["t", pie_source], ["t", pie_source]] }).each { |r| r[:occurrence] = 0 }

      expect { described_class.migration_manifest(old_records: old_records, new_records: collided) }
        .to raise_error(CorpusCaseIdentity::CollisionError)
    end

    it "raises when the old records collide" do
      collided = old_records.map { |record| record.merge(occurrence: 0, title: "t", source: pie_source) }

      expect do
        described_class.migration_manifest(old_records: collided, new_records: records_from({ path => [first] }))
      end.to raise_error(CorpusCaseIdentity::CollisionError)
    end

    it "raises when one old case is listed twice" do
      repeated = old_records.map { |record| record.merge(case: "pie/001_same.mmd") }

      expect do
        described_class.migration_manifest(old_records: repeated, new_records: [])
      end.to raise_error(CorpusCaseIdentity::InvalidRecordError, /listed twice/)
    end
  end
end
