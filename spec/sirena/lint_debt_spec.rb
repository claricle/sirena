# frozen_string_literal: true

require "spec_helper"
require "sirena/lint_debt"
require_relative "../support/lint_debt_fixture"
require "fileutils"
require "yaml"

RSpec.describe Sirena::LintDebt do
  include LintDebtFixture

  after { FileUtils.rm_rf(root) }

  let(:debt) { described_class.new(root: root) }

  describe "#rows and #total" do
    it "reports the exact rows the fixture carries" do
      expect(debt.rows.map { |r| [r.cop, r.file, r.count] }).to eq(
        [["Style/FrozenStringLiteralComment", "debt.rb", 1]],
      )
      expect(debt.total).to eq(1)
    end

    it "contributes zero rows for a clean file" do
      expect(debt.rows.map(&:file)).not_to include("clean.rb")
    end
  end

  describe "#by_source" do
    it "attributes the fixture's one offence to the todo layer" do
      expect(debt.by_source).to eq("todo" => 1, "config" => 0, "inline" => 0)
    end
  end

  describe "inertness to .rubocop.yml" do
    it "ignores a fresh local inherit_from suppressing everything" do
      write(".rubocop_extra.yml", "AllCops:\n  DisabledByDefault: true\n")
      write(
        ".rubocop.yml",
        "inherit_from:\n  - .rubocop_todo.yml\n  - .rubocop_extra.yml\n" \
        "AllCops:\n  NewCops: enable\n",
      )

      expect(debt.total).to eq(1)
    end

    it "ignores a fresh cop-level Exclude added directly" do
      write(
        ".rubocop.yml",
        "inherit_from:\n  - .rubocop_todo.yml\nAllCops:\n  NewCops: enable\n" \
        "Style/FrozenStringLiteralComment:\n  Exclude:\n    - debt.rb\n",
      )

      expect(debt.total).to eq(1)
    end

    it "ignores an inline rubocop:disable directive" do
      write(
        "inline.rb",
        "# frozen_string_literal: true\n\n" \
        "module Fixture\n  " \
        "X = 1+1 " \
        "# rubocop:disable Layout/SpaceAroundOperators\n" \
        "end\n",
      )

      expect(debt.rows.map { |r| [r.cop, r.file] }).to include(
        ["Layout/SpaceAroundOperators", "inline.rb"],
      )
    end
  end

  describe "ambient options" do
    it "ignores RUBOCOP_OPTS" do
      original = ENV.fetch("RUBOCOP_OPTS", nil)
      ENV["RUBOCOP_OPTS"] = "--only Lint/Syntax"

      expect(debt.total).to eq(1)
    ensure
      ENV["RUBOCOP_OPTS"] = original
    end

    it "refuses to run under a .rubocop options dotfile" do
      write(".rubocop", "--format simple\n")

      expect { debt }.to raise_error(
        described_class::ExecutionError, /\.rubocop/
      )
    end
  end

  describe "exit-code handling" do
    it "raises when rubocop cannot run its config" do
      write(
        ".rubocop.yml",
        "inherit_from:\n  - https://example.invalid/does-not-exist.yml\n",
      )

      expect { debt.total }.to raise_error(described_class::ExecutionError)
    end
  end

  describe "the signed exception allowlist" do
    def write_exceptions(entries)
      write(
        "scoreboard/lint-exceptions.yml", { "exceptions" => entries }.to_yaml
      )
    end

    it "subtracts nothing when empty" do
      write_exceptions([])
      expect(debt.total).to eq(1)
    end

    it "subtracts an eligible metrics-cop row on a grammar-path file" do
      grammar_file = "lib/sirena/parser/grammars/flowchart.rb"
      body = Array.new(12) { |i| "    x#{i} = #{i}\n" }.join
      write(
        grammar_file,
        "# frozen_string_literal: true\n\n" \
        "module Fixture\n  " \
        "def self.long_method\n#{body}  end\nend\n",
      )
      write_exceptions(
        [{ "cop" => "Metrics/MethodLength", "file" => grammar_file }],
      )

      expect(debt.rows.map(&:cop)).not_to include("Metrics/MethodLength")
      expect(debt.exceptions_applied).to eq(1)
    end

    it "refuses a cop outside the metrics class" do
      grammar_file = "lib/sirena/parser/grammars/flowchart.rb"
      write(grammar_file, "module X; end\n")
      write_exceptions(
        [{ "cop" => "Style/FrozenStringLiteralComment", "file" => "debt.rb" }],
      )

      expect { debt.total }.to raise_error(
        described_class::ExecutionError, /metrics class/
      )
    end

    it "refuses a file outside the grammar path" do
      write_exceptions(
        [{ "cop" => "Metrics/MethodLength", "file" => "debt.rb" }],
      )

      expect { debt.total }.to raise_error(
        described_class::ExecutionError, /grammars/
      )
    end

    it "refuses an entry whose file does not exist" do
      write_exceptions(
        [
          {
            "cop" => "Metrics/MethodLength",
            "file" => "lib/sirena/parser/grammars/missing.rb",
          },
        ],
      )

      expect { debt.total }.to raise_error(
        described_class::ExecutionError, /does not exist/
      )
    end

    it "refuses a stale entry matching no current row" do
      grammar_file = "lib/sirena/parser/grammars/flowchart.rb"
      write(grammar_file, "module X; end\n")
      write_exceptions(
        [{ "cop" => "Metrics/MethodLength", "file" => grammar_file }],
      )

      expect { debt.total }.to raise_error(
        described_class::ExecutionError, /no current offence/
      )
    end
  end
end
