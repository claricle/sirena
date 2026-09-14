# frozen_string_literal: true

require "spec_helper"
require "sirena/lint_debt"
require "sirena/lint_debt_scoreboard"
require_relative "../support/lint_debt_fixture"
require "fileutils"
require "yaml"

RSpec.describe Sirena::LintDebtScoreboard do
  include LintDebtFixture

  after { FileUtils.rm_rf(root) }

  # A fresh instance every call, never memoised -- each example measures
  # the tree more than once (baseline, then again after a mutation), and
  # Sirena::LintDebt caches its own measurement for its own lifetime.
  def board
    described_class.new(root: root, debt: Sirena::LintDebt.new(root: root))
  end

  describe "#record!" do
    context "when recording for the first time" do
      let(:summary) { board.record! }
      let(:cop_file) do
        YAML.safe_load_file(
          File.join(board.directory, "Style-FrozenStringLiteralComment.yml"),
        )
      end

      before { summary }

      it "reports a bootstrap" do
        expect(summary[:bootstrap]).to be(true)
      end

      it "marks the scoreboard as recorded without an override" do
        expect(File.read(File.join(board.directory, "_meta.yml"))).to include(
          "recorded_with_override: false",
        )
      end

      it "stores the fixture's one cop file" do
        expect(cop_file).to eq(
          "cop" => "Style/FrozenStringLiteralComment",
          "rows" => [{ "file" => "debt.rb", "count" => 1 }],
        )
      end
    end

    it "refuses to record a new row without the override" do
      board.record!
      write("second.rb", "module Fixture\n  Y = 'x'.freeze\nend\n")

      expect { board.record! }.to raise_error(
        described_class::RefusedError, /debt increased/
      )
    end

    context "when an existing row's count increases" do
      before do
        write(
          "op.rb",
          "# frozen_string_literal: true\n\nmodule Fixture\n  X = 1+1\nend\n",
        )
        board.record!

        write(
          "op.rb",
          "# frozen_string_literal: true\n\n" \
          "module Fixture\n  X = 1+1\n  Y = 2+2\nend\n",
        )
      end

      it "refuses the record without the override" do
        expect { board.record! }.to raise_error(
          described_class::RefusedError, /debt increased/
        )
      end
    end

    context "when recording with the override" do
      before do
        board.record!
        write("second.rb", "module Fixture\n  Y = 'x'.freeze\nend\n")

        ENV["SIRENA_LINT_DEBT_ALLOW_INCREASE"] = "1"
        board.record!
        ENV.delete("SIRENA_LINT_DEBT_ALLOW_INCREASE")
      end

      it "marks the scoreboard as recorded with an override" do
        expect(File.read(File.join(board.directory, "_meta.yml"))).to include(
          "recorded_with_override: true",
        )
      end

      it "clears the override marker on the next clean record" do
        board.record!

        expect(File.read(File.join(board.directory, "_meta.yml"))).to include(
          "recorded_with_override: false",
        )
      end
    end

    context "when a cop's rows drop to zero" do
      before do
        board.record!
        write(".rubocop_todo.yml", "")
        write(
          "debt.rb",
          "# frozen_string_literal: true\n\n" \
          "module Fixture\n  VALUE = 'debt'\nend\n",
        )

        ENV["SIRENA_LINT_DEBT_ALLOW_INCREASE"] = "1"
        board.record!
        ENV.delete("SIRENA_LINT_DEBT_ALLOW_INCREASE")
      end

      it "prunes the cop's scoreboard file" do
        cop_file = File.join(
          board.directory, "Style-FrozenStringLiteralComment.yml"
        )
        expect(File.exist?(cop_file)).to be(false)
      end
    end
  end

  describe "#diff" do
    it "is clean when nothing changed" do
      board.record!
      expect(board.diff).to be_clean
    end

    context "with an offence seeded via the todo file (route A)" do
      before do
        board.record!
        write("seed_a.rb", "module Fixture\n  Y = 'seed_a'.freeze\nend\n")
        todo = File.read(File.join(root, ".rubocop_todo.yml"))
        write(
          ".rubocop_todo.yml",
          "#{todo}Style/FrozenStringLiteralComment:\n  " \
          "Exclude:\n    - seed_a.rb\n",
        )
      end

      let(:diff) { board.diff }

      it "is not clean" do
        expect(diff).not_to be_clean
      end

      it "flags the seeded offence as added" do
        expect(diff.added).to include(
          ["Style/FrozenStringLiteralComment", "seed_a.rb"],
        )
      end
    end

    context "with an offence seeded via a fresh Exclude (route B)" do
      before do
        board.record!
        write("seed_b.rb", "module Fixture\n  Y = 'seed_b'.freeze\nend\n")
        write(
          ".rubocop.yml",
          "inherit_from:\n  - .rubocop_todo.yml\n" \
          "AllCops:\n  NewCops: enable\n" \
          "Style/FrozenStringLiteralComment:\n  Exclude:\n    - seed_b.rb\n",
        )
      end

      let(:diff) { board.diff }

      it "is not clean" do
        expect(diff).not_to be_clean
      end

      it "flags the seeded offence as added" do
        expect(diff.added).to include(
          ["Style/FrozenStringLiteralComment", "seed_b.rb"],
        )
      end
    end

    context "with an offence seeded via an inline directive (route C)" do
      before do
        board.record!
        write(
          "seed_c.rb",
          "# frozen_string_literal: true\n\n" \
          "module Fixture\n  " \
          "Y = 1+1 " \
          "# rubocop:disable Layout/SpaceAroundOperators\n" \
          "end\n",
        )
      end

      let(:diff) { board.diff }

      it "is not clean" do
        expect(diff).not_to be_clean
      end

      it "flags the seeded offence as added" do
        expect(diff.added).to include(
          ["Layout/SpaceAroundOperators", "seed_c.rb"],
        )
      end
    end

    context "when an existing row's count increases" do
      before do
        write(
          "op.rb",
          "# frozen_string_literal: true\n\nmodule Fixture\n  X = 1+1\nend\n",
        )
        board.record!

        write(
          "op.rb",
          "# frozen_string_literal: true\n\n" \
          "module Fixture\n  X = 1+1\n  Y = 2+2\nend\n",
        )
      end

      let(:diff) { board.diff }

      it "is not clean" do
        expect(diff).not_to be_clean
      end

      it "reports the row as changed" do
        rows = diff.changed.map { |c| [c.cop, c.file, c.from, c.to] }

        expect(rows).to include(["Layout/SpaceAroundOperators", "op.rb", 1, 2])
      end
    end

    context "when an offence is fixed" do
      before do
        write(
          "op.rb",
          "# frozen_string_literal: true\n\nmodule Fixture\n  X = 1+1\nend\n",
        )
        board.record!

        write(
          "op.rb",
          "# frozen_string_literal: true\n\nmodule Fixture\n  X = 1 + 1\nend\n",
        )
      end

      let(:diff) { board.diff }

      it "is not clean" do
        expect(diff).not_to be_clean
      end

      it "reports the row as removed" do
        expect(diff.removed).to include(
          ["Layout/SpaceAroundOperators", "op.rb"],
        )
      end
    end
  end
end
