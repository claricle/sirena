# frozen_string_literal: true

require "fileutils"
require "date"
require "digest"
require "json"
require "open3"
require "rexml/document"
require_relative "../scripts/hardened_mmdc"
require_relative "../scripts/mermaid_toolchain"
require_relative "support/mermaid_fixture_reference_generator"
require_relative "support/mermaid_fixture_generator"
require_relative "support/mermaid_fixture_output_comparator"

# Implementations of the mermaid:* task entry points.
module MermaidFixtureTasks
  extend self

  def generate_fixtures(diagram_type)
    puts "Generating Mermaid.js fixtures for: #{diagram_type}"
    puts "=" * 60
    verify_cli
    generator = MermaidFixtureGenerator.new
    if diagram_type == "all"
      generator.generate_all_fixtures
    else
      generator.generate_fixtures_for_type(diagram_type)
    end
  end

  def verify_cli
    MermaidToolchain.verify_toolchain
    version, status = Open3.capture2e(*MermaidToolchain.version_command)
    raise "pinned mermaid-cli failed: #{version}" unless status.success?

    puts "✅ Found pinned mermaid-cli: #{version.strip}"
    puts
  end

  def generate_missing_references
    generated = MermaidReferenceGenerator.new.generate
    puts "Generated #{generated.length} missing Mermaid reference(s)"
  end

  def check_reference_provenance
    checked = MermaidReferenceGenerator.new.verify_provenance!
    puts "Verified #{checked} generated Mermaid reference(s)"
  end

  def compare(diagram_type)
    puts "Comparing Sirena vs Mermaid.js output for: #{diagram_type}"
    puts "=" * 60
    puts
    comparator = MermaidOutputComparator.new
    if diagram_type == "all"
      comparator.compare_all_types
    else
      comparator.compare_type(diagram_type)
    end
  end

  def validate
    puts "Validating Sirena parsers against Mermaid test suite"
    puts "=" * 60
    puts
    results = MermaidTestValidator.new.validate_all
    puts "\n#{'=' * 60}"
    puts "VALIDATION SUMMARY"
    puts "=" * 60
    results.each { |type, result| print_validation_type(type, result) }
    print_validation_total(results)
  end

  def print_validation_type(type, result)
    status = result[:passing] == result[:total] ? "✅" : "⚠️ "
    puts format("%<type>-20s %<status>s %<passing>3d/%<total>3d passing " \
                "(%<rate>.1f%%)",
                type: type, status: status,
                passing: result[:passing], total: result[:total],
                rate: result[:passing].to_f / result[:total] * 100)
  end

  def print_validation_total(results)
    passing = results.values.sum { |result| result[:passing] }
    total = results.values.sum { |result| result[:total] }
    percentage = (passing.to_f / total * 100)
    puts format("\n%<label>-20s    %<passing>3d/%<total>3d passing " \
                "(%<rate>.1f%%)", label: "OVERALL", passing: passing,
                                  total: total, rate: percentage)
  end

  private_class_method :verify_cli, :print_validation_type,
                       :print_validation_total
end

namespace :mermaid do
  desc "Generate SVG fixtures from mermaid-js for comparison and testing"
  task :generate_fixtures, [:diagram_type] do |_task, args|
    MermaidFixtureTasks.generate_fixtures(args[:diagram_type] || "all")
  end
  desc "Generate missing oracle-valid references with pinned provenance"
  task(:generate_missing_references) do
    MermaidFixtureTasks.generate_missing_references
  end
  desc "Check generated Mermaid reference provenance and checksums"
  task(:check_reference_provenance) do
    MermaidFixtureTasks.check_reference_provenance
  end
  desc "Compare Sirena output with Mermaid.js reference fixtures"
  task :compare, [:diagram_type] do |_task, args|
    MermaidFixtureTasks.compare(args[:diagram_type] || "all")
  end
  desc "Validate all Sirena parsers against Mermaid test suite"
  task(:validate) { MermaidFixtureTasks.validate }
end
