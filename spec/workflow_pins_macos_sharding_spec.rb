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
        matrix.fetch("exclude", []).any? { |exclude| exclude <= cell }
      end + matrix.fetch("include")
    end
    let(:signatures) do
      cells.map do |cell|
        cell.values_at("ruby", "os", "shard", "experimental").join("|")
      end
    end
    let(:expected_cells) do
      %w[
        3.2|ubuntu-latest||false 3.3|ubuntu-latest||false
        3.4|ubuntu-latest||false
        3.2|macos-latest||false 3.3|macos-latest||false
        3.4|macos-latest||false
        3.2|windows-latest||false 3.3|windows-latest||false
        3.4|windows-latest||false
        4.0|ubuntu-latest||true 4.0|macos-latest||true
        4.0|windows-latest||true
      ]
    end

    it "runs every Ruby and OS combination exactly once" do
      expect(signatures.sort).to eq(expected_cells.sort)
    end
  end

  context "with complete suite execution" do
    let(:expected_label) do
      "unit (ruby ${{ matrix.ruby }}, ${{ matrix.os }})"
    end

    it "labels the combination and leaves shard selection unset" do
      step = unit.fetch("steps").find { |row| row["run"] == "bundle exec rake" }
      expect([unit.fetch("name"), step.dig("env", "SIRENA_SPEC_SHARD")])
        .to eq([expected_label, nil])
    end
  end

  context "with the existing source partition utility" do
    let(:shards) { (1..3).map { |index| Sirena::SpecShard.new(index, 3) } }
    let(:all_files) do
      benchmarks = Dir.glob("spec/benchmarks/**/*_spec.rb")
      (Dir.glob(Sirena::SpecShard::PATTERN) - benchmarks).uniq.sort
    end

    it "runs every unit file exactly once across its groups" do
      expect(shards.flat_map(&:files).sort).to eq(all_files)
    end

    it "assigns the retained benchmark and guard tail only to the last group" do
      expect(shards.map(&:runs_tail?)).to eq([false, false, true])
    end
  end
end
