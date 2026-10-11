# frozen_string_literal: true

require "spec_helper"
require "digest"
require "yaml"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Recomputes every oracle-valid PlantUML sequence case against its pinned
# reference and compares the result with the committed ledger.
module Plantuml
  module SequenceLayoutParity
    extend self

    def self.memoized_rows
      @memoized_rows ||= measured_rows
    end

    # Re-records the ledger after a measured improvement:
    #   bundle exec ruby -Ispec -rrspec \
    #     -e 'require "./spec/plantuml/sequence_layout_parity_spec"' \
    #     -e "Plantuml::SequenceLayoutParity.record!"
    def self.record!
      Sirena::Notation.register(Sirena::Notation::PlantUML)
      path = File.join(ROOT, "sequence_layout_parity.yml")
      header = File.readlines(path).take_while { |line| line.start_with?("#") }
      rows = measured_rows.sort_by { |row| row["case"] }
      yaml = { "rows" => rows }.to_yaml.delete_prefix("---\n")
      File.write(path, header.join + yaml)
    end

    ROOT = File.expand_path(__dir__)
    REPRODUCE = "spec/plantuml/sequence_layout_parity_spec.rb"
    ERROR_STATUS = "comparison-error"
    BARS = {
      "worst_e_c" => 0.08, "worst_e_w" => 0.15,
      "worst_e_h" => 0.15, "worst_e_a" => 0.15
    }.freeze

    def ledger
      YAML.load_file(File.join(ROOT, "sequence_layout_parity.yml"))
    end

    def provenance
      path = File.join(ROOT, "references", "sequence", "provenance.yml")
      YAML.load_file(path)
    end

    def case_ids
      valid_ids.select { |id| File.file?(source_path(id)) }.sort
    end

    def valid_ids
      verdicts = YAML.load_file(File.join(ROOT, "oracle-verdicts.yml"))
      verdicts.fetch("verdicts").filter_map do |row|
        id = row["id"]
        id.delete_prefix("sequence/") if row["verdict"] == "valid" &&
                                         id.start_with?("sequence/")
      end
    end

    def source_path(id)
      File.join(ROOT, "sequence", "#{id}.puml")
    end

    def reference_path(id)
      File.join(ROOT, "references", "sequence", "#{id}.svg")
    end

    def digest(path)
      Digest::SHA256.file(path).hexdigest if File.file?(path)
    end

    def evidence_failures
      cases = provenance.fetch("cases")
      case_ids.flat_map do |id|
        record = cases.fetch(id, {})
        [[:source, source_path(id)], [:reference, reference_path(id)]]
          .filter_map do |kind, path|
          "#{id}: #{kind}" if record["#{kind}_sha256"] != digest(path)
        end
      end
    end

    def result_for(id)
      reference = reference_path(id)
      SpecSupport::LayoutParity::CaseComparator.compare(
        case_id: "plantuml/sequence/#{id}", type: "plantuml_sequence",
        reference: reference, reference_svg: File.read(reference),
        sirena_svg: Sirena.render(File.read(source_path(id)),
                                  notation: :plantuml),
        reproduce: "bundle exec rspec #{REPRODUCE}",
        recognizer: SpecSupport::LayoutParity::PlantumlSequenceRecognizer.new,
        spatial_kinds: [:participant]
      )
    end

    # The extractor raises on a Sirena path it cannot read (short cubic
    # arguments); the ledger pins that as its own status instead.
    def row_for(id)
      row = SpecSupport::LayoutParity::CaseLedger.build([result_for(id)]).first
      ledger_row(row)
    rescue ArgumentError
      error_row(id)
    end

    def measured_rows
      case_ids.map { |id| row_for(id) }
    end

    def error_row(id)
      { "case" => id, "matched" => 0, "status" => ERROR_STATUS,
        "summary" => { "hard_failure" => true, "metrics" => nil } }
    end

    def ledger_row(row)
      geometry = row.fetch("geometry")
      {
        "case" => row.fetch("case").delete_prefix("plantuml/sequence/"),
        "summary" => row.fetch("summary"),
        "matched" => geometry.fetch("matched"),
        "status" => status(row.fetch("summary")),
      }
    end

    def status(summary)
      return "hard-failure" if summary.fetch("hard_failure")

      metrics = summary.fetch("metrics").slice(*BARS.keys)
      over = metrics.any? { |key, value| value && value > BARS.fetch(key) }
      over ? "miss" : "pass"
    end

    def committed_rows
      ledger.fetch("rows")
    end

    def fresh_rows
      SequenceLayoutParity.memoized_rows
    end

    def outcomes(rows)
      rows.to_h { |row| [row["case"], row.values_at("status", "matched")] }
    end

    def diff
      SpecSupport::LayoutParity::ScoreboardRatchet.diff(
        committed: committed_rows.map { |row| ratchet_row(row) },
        fresh: fresh_rows.map { |row| ratchet_row(row) },
      )
    end

    # ScoreboardRatchet reads only the summary; an error row has no metrics.
    def ratchet_row(row)
      return row unless row.fetch("summary").fetch("metrics").nil?

      nil_metrics = SpecSupport::LayoutParity::CaseLedger::METRICS
        .to_h { |metric| [metric, nil] }
      summary = row.fetch("summary").merge("metrics" => nil_metrics)
      row.merge("summary" => summary)
    end
  end
end

RSpec.describe Plantuml::SequenceLayoutParity do
  include_context "with an isolated notation registry"
  include described_class

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "has pinned provenance for every oracle-valid sequence case" do
    expect([case_ids.size, evidence_failures]).to eq([77, []])
  end

  it "records exactly the oracle-valid sequence cases in the ledger" do
    expect(committed_rows.map { |row| row["case"] }.sort).to eq(case_ids)
  end

  it "has no case worse than its ledger row" do
    expect(diff.fetch(:regressions)).to eq([])
  end

  it "has no improvement missing from the ledger" do
    expect(diff.fetch(:unrecorded_improvements)).to eq([])
  end

  it "has no stale ledger row after a status or count change" do
    expect(diff.slice(:missing, :new)).to eq(missing: [], new: [])
  end

  it "keeps the recorded status and matched count of every case" do
    expect(outcomes(fresh_rows)).to eq(outcomes(committed_rows))
  end
end
