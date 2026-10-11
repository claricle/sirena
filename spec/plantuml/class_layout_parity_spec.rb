# frozen_string_literal: true

require "spec_helper"
require "digest"
require "yaml"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Recomputes every oracle-valid PlantUML class case against its pinned
# reference and compares the result with the committed ledger.
module Plantuml
  module ClassLayoutParity
    extend self

    def self.memoized_rows
      @memoized_rows ||= measured_rows
    end

    # Re-records the ledger after a measured improvement:
    #   bundle exec ruby -Ispec -rrspec \
    #     -e 'require "./spec/plantuml/class_layout_parity_spec"' \
    #     -e "Plantuml::ClassLayoutParity.record!"
    def self.record!
      Sirena::Notation.register(Sirena::Notation::PlantUML)
      path = File.join(ROOT, "class_layout_parity.yml")
      header = File.readlines(path).take_while { |line| line.start_with?("#") }
      rows = measured_rows.sort_by { |row| row["case"] }
      yaml = { "rows" => rows }.to_yaml.delete_prefix("---\n")
      File.write(path, header.join + yaml)
    end

    ROOT = File.expand_path(__dir__)
    REPRODUCE = "spec/plantuml/class_layout_parity_spec.rb"
    BARS = {
      "worst_e_c" => 0.08, "worst_e_w" => 0.15,
      "worst_e_h" => 0.15, "worst_e_a" => 0.15
    }.freeze

    def ledger
      YAML.load_file(File.join(ROOT, "class_layout_parity.yml"))
    end

    def provenance
      YAML.load_file(File.join(ROOT, "references", "class", "provenance.yml"))
    end

    def case_ids
      valid_ids.select { |id| File.file?(source_path(id)) }.sort
    end

    def valid_ids
      verdicts = YAML.load_file(File.join(ROOT, "oracle-verdicts.yml"))
      verdicts.fetch("verdicts").filter_map do |row|
        row["id"].delete_prefix("class/") if row["verdict"] == "valid" &&
                                             row["id"].start_with?("class/")
      end
    end

    def source_path(id)
      File.join(ROOT, "class", "#{id}.puml")
    end

    def reference_path(id)
      File.join(ROOT, "references", "class", "#{id}.svg")
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
        case_id: "plantuml/class/#{id}", type: "plantuml_class",
        reference: reference, reference_svg: File.read(reference),
        sirena_svg: Sirena.render(File.read(source_path(id)),
                                  notation: :plantuml),
        reproduce: "bundle exec rspec #{REPRODUCE}",
        recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
        spatial_kinds: [:class]
      )
    end

    def measured_rows
      results = case_ids.map { |id| result_for(id) }
      SpecSupport::LayoutParity::CaseLedger.build(results).map do |row|
        ledger_row(row)
      end
    end

    def ledger_row(row)
      geometry = row.fetch("geometry")
      {
        "case" => row.fetch("case").delete_prefix("plantuml/class/"),
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
      ClassLayoutParity.memoized_rows
    end

    def outcomes(rows)
      rows.to_h { |row| [row["case"], row.values_at("status", "matched")] }
    end

    def diff
      SpecSupport::LayoutParity::ScoreboardRatchet.diff(
        committed: committed_rows, fresh: fresh_rows,
      )
    end
  end
end

RSpec.describe Plantuml::ClassLayoutParity do
  include_context "with an isolated notation registry"
  include described_class

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "has pinned provenance for every oracle-valid class case" do
    expect([case_ids.size, evidence_failures]).to eq([35, []])
  end

  it "records exactly the oracle-valid class cases in the ledger" do
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
