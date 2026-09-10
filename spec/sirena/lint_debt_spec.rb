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
    end

    it "reports the fixture's total offence count" do
      expect(debt.total).to eq(1)
    end

    it "contributes zero rows for a clean file" do
      expect(debt.rows.map(&:file)).not_to include("clean.rb")
    end

    context "with a Gemfile using paren-call gem syntax" do
      before do
        write(
          "Gemfile",
          "source 'https://rubygems.org'\ngemspec\n" \
          "gem('rubocop-rspec', '= 3.9.0')\n",
        )
        write(
          "plugin_spec.rb",
          "# frozen_string_literal: true\n\n" \
          "RSpec.describe Fixture do\n  " \
          "it 'does something', :skip do\n  end\nend\n",
        )
      end

      it "derives the plugin a text pattern would miss" do
        expect(debt.rows.map(&:cop)).to include("RSpec/PendingWithoutReason")
      end
    end
  end

  describe "#by_source" do
    it "attributes the fixture's one offence to the todo layer" do
      expect(debt.by_source).to eq("todo" => 1, "config" => 0, "inline" => 0)
    end
  end

  describe "inertness to .rubocop.yml" do
    context "with a fresh local inherit_from suppressing everything" do
      before do
        write(".rubocop_extra.yml", "AllCops:\n  DisabledByDefault: true\n")
        write(
          ".rubocop.yml",
          "inherit_from:\n  - .rubocop_todo.yml\n  - .rubocop_extra.yml\n" \
          "AllCops:\n  NewCops: enable\n",
        )
      end

      it "still reports the fixture's one offence" do
        expect(debt.total).to eq(1)
      end
    end

    context "with a fresh cop-level Exclude added directly" do
      before do
        write(
          ".rubocop.yml",
          "inherit_from:\n  - .rubocop_todo.yml\n" \
          "AllCops:\n  NewCops: enable\n" \
          "Style/FrozenStringLiteralComment:\n  Exclude:\n    - debt.rb\n",
        )
      end

      it "still reports the fixture's one offence" do
        expect(debt.total).to eq(1)
      end
    end

    context "with an inline rubocop:disable directive" do
      before do
        write(
          "inline.rb",
          "# frozen_string_literal: true\n\n" \
          "module Fixture\n  " \
          "X = 1+1 " \
          "# rubocop:disable Layout/SpaceAroundOperators\n" \
          "end\n",
        )
      end

      it "still reports the disabled offence" do
        expect(debt.rows.map { |r| [r.cop, r.file] }).to include(
          ["Layout/SpaceAroundOperators", "inline.rb"],
        )
      end
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

    def write_long_method_offence(file)
      body = Array.new(12) { |i| "    x#{i} = #{i}\n" }.join
      write(
        file,
        "# frozen_string_literal: true\n\n" \
        "module Fixture\n  " \
        "def self.long_method\n#{body}  end\nend\n",
      )
    end

    let(:grammar_file) { "lib/sirena/parser/grammars/flowchart.rb" }

    # The allowlist file states every entry carries four fields; the code
    # required two, so an entry naming nobody and dated never was subtracted
    # from the debt in silence. Each half is pinned separately -- one example
    # asserting "some field is required" passes while the other goes
    # unchecked.
    let(:err_class) { Sirena::LintDebt::ExecutionError }

    def signed_entry
      { "cop" => "Metrics/MethodLength", "file" => grammar_file,
        "approved_by" => "r", "approved_on" => "2026-09-10" }
    end

    # A `def`, not a `let`: it takes an argument, and `let` has no arity.
    # The message must be right for THIS field, not merely mention it --
    # `/approved_on is/` passed while the text told the reader to add a
    # name when what they needed was a date.
    def signature_message(field)
      tail = field == "approved_by" ? "name who signed" : "carry the date"
      Regexp.new("#{field} is required and must #{tail}")
    end

    %w[approved_by approved_on].each do |field|
      it "refuses an exception missing #{field}" do
        write_long_method_offence(grammar_file)
        write_exceptions([signed_entry.reject { |k, _| k == field }])

        expect { debt.total }
          .to raise_error(err_class, signature_message(field))
      end

      it "refuses a blank #{field}" do
        write_long_method_offence(grammar_file)
        write_exceptions([signed_entry.merge(field => "  ")])

        expect { debt.total }
          .to raise_error(err_class, signature_message(field))
      end
    end

    it "subtracts nothing when empty" do
      write_exceptions([])
      expect(debt.total).to eq(1)
    end

    context "with an eligible metrics-cop row on a grammar-path file" do
      before do
        write_long_method_offence(grammar_file)
        write_exceptions(
          [{ "cop" => "Metrics/MethodLength", "file" => grammar_file,
             "approved_by" => "r", "approved_on" => "2026-09-10" }],
        )
      end

      it "subtracts the row from #rows" do
        expect(debt.rows.map(&:cop)).not_to include("Metrics/MethodLength")
      end

      it "counts the exception as applied" do
        expect(debt.exceptions_applied).to eq(1)
      end
    end

    context "with an unquoted YAML date in approved_on" do
      before do
        write_long_method_offence(grammar_file)
        write(
          "scoreboard/lint-exceptions.yml",
          "exceptions:\n  " \
          "- cop: Metrics/MethodLength\n    " \
          "file: #{grammar_file}\n    " \
          "approved_by: reviewer\n    " \
          "approved_on: 2026-09-10\n",
        )
      end

      it "accepts the date instead of crashing the loader" do
        expect(debt.rows.map(&:cop)).not_to include("Metrics/MethodLength")
      end

      it "counts the exception as applied" do
        expect(debt.exceptions_applied).to eq(1)
      end
    end

    context "with a cop outside the metrics class" do
      before do
        write(grammar_file, "module X; end\n")
        write_exceptions(
          [
            {
              "cop" => "Style/FrozenStringLiteralComment",
              "file" => "debt.rb",
              "approved_by" => "r",
              "approved_on" => "2026-09-10",
            },
          ],
        )
      end

      it "refuses the exception" do
        expect { debt.total }.to raise_error(
          described_class::ExecutionError, /metrics class/
        )
      end
    end

    context "with a file outside the grammar path" do
      before do
        write_exceptions(
          [{ "cop" => "Metrics/MethodLength", "file" => "debt.rb",
             "approved_by" => "r", "approved_on" => "2026-09-10" }],
        )
      end

      it "refuses the exception" do
        expect { debt.total }.to raise_error(
          described_class::ExecutionError, /grammars/
        )
      end
    end

    context "with an entry whose file does not exist" do
      before do
        write_exceptions(
          [
            {
              "cop" => "Metrics/MethodLength",
              "file" => "lib/sirena/parser/grammars/missing.rb",
              "approved_by" => "r",
              "approved_on" => "2026-09-10",
            },
          ],
        )
      end

      it "refuses the exception" do
        expect { debt.total }.to raise_error(
          described_class::ExecutionError, /does not exist/
        )
      end
    end

    context "with a stale entry matching no current row" do
      before do
        write(grammar_file, "module X; end\n")
        write_exceptions(
          [{ "cop" => "Metrics/MethodLength", "file" => grammar_file,
             "approved_by" => "r", "approved_on" => "2026-09-10" }],
        )
      end

      it "refuses the exception" do
        expect { debt.total }.to raise_error(
          described_class::ExecutionError, /no current offence/
        )
      end
    end
  end
end
