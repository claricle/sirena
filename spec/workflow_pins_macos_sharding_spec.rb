# frozen_string_literal: true

require "yaml"
require_relative "../scripts/check_workflow_pins"
require_relative "../tasks/support/spec_shard"

RSpec.describe WorkflowPins do
  let(:workflow) { YAML.safe_load_file(".github/workflows/ci.yml") }
  let(:unit) { workflow.fetch("jobs").fetch("unit") }

  context "with the expanded Ruby and OS matrix" do
    let(:cells) do
      matrix = unit.fetch("strategy").fetch("matrix")
      axes = matrix.except("include", "exclude")
      base = axes.values.first.product(*axes.values.drop(1)).map do |values|
        axes.keys.zip(values).to_h
      end
      base.reject do |cell|
        matrix.fetch("exclude").any? { |exclude| exclude <= cell }
      end + matrix.fetch("include")
    end
    let(:signatures) do
      cells.map do |cell|
        cell.values_at("ruby", "os", "shard", "experimental").join("|")
      end
    end
    let(:expected_cells) do
      %w[
        3.2|ubuntu-latest|1/3|false 3.3|ubuntu-latest|1/3|false
        3.4|ubuntu-latest|1/3|false
        3.2|macos-latest|1/3|false 3.3|macos-latest|1/3|false
        3.4|macos-latest|1/3|false 3.4|macos-latest|2/3|false
        3.4|macos-latest|3/3|false
        3.2|windows-latest|1/3|false 3.2|windows-latest|2/3|false
        3.2|windows-latest|3/3|false 3.3|windows-latest|1/3|false
        3.3|windows-latest|2/3|false 3.3|windows-latest|3/3|false
        3.4|windows-latest|1/3|false 3.4|windows-latest|2/3|false
        3.4|windows-latest|3/3|false
        4.0|ubuntu-latest||true 4.0|macos-latest||true
        4.0|windows-latest|1/3|true 4.0|windows-latest|2/3|true
        4.0|windows-latest|3/3|true
      ]
    end

    it "changes only macOS Ruby 3.4 from one job to three" do
      expect(signatures.sort).to eq(expected_cells.sort)
    end
  end

  context "with shard labels and execution" do
    let(:sharding_condition) do
      "(matrix.os == 'windows-latest' || " \
        "(matrix.os == 'macos-latest' && matrix.ruby == '3.4'))"
    end
    let(:expected_env) do
      "${{ #{sharding_condition} && matrix.shard || '' }}"
    end
    let(:expected_label) do
      "unit (ruby ${{ matrix.ruby }}, ${{ matrix.os }}${{ " \
        "#{sharding_condition} && format(', shard {0}', matrix.shard) || '' }})"
    end

    it "selects the same Windows and macOS cells for labels and execution" do
      step = unit.fetch("steps").find { |row| row["run"] == "bundle exec rake" }
      expect([unit.fetch("name"), step.dig("env", "SIRENA_SPEC_SHARD")])
        .to eq([expected_label, expected_env])
    end
  end

  context "with the actual source partition" do
    let(:shards) { (1..3).map { |index| Sirena::SpecShard.new(index, 3) } }
    let(:all_files) do
      benchmarks = Dir.glob("spec/benchmarks/**/*_spec.rb")
      (Dir.glob(Sirena::SpecShard::PATTERN) - benchmarks).uniq.sort
    end

    it "runs every unit file exactly once across the macOS groups" do
      expect(shards.flat_map(&:files).sort).to eq(all_files)
    end

    it "assigns the retained benchmark and guard tail only to the last group" do
      expect(shards.map(&:runs_tail?)).to eq([false, false, true])
    end
  end
end
