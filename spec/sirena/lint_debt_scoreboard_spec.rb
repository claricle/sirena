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
    it "bootstraps without needing the override" do
      summary = board.record!

      expect(summary[:bootstrap]).to be(true)
      expect(File.read(File.join(board.directory, "_meta.yml"))).to include(
        "recorded_with_override: false",
      )
      stored = YAML.safe_load_file(
        File.join(board.directory, "Style-FrozenStringLiteralComment.yml"),
      )
      expect(stored).to eq(
        "cop" => "Style/FrozenStringLiteralComment",
        "rows" => [{ "file" => "debt.rb", "count" => 1 }],
      )
    end

    it "refuses to record a new row without the override" do
      board.record!
      write("second.rb", "module Fixture\n  Y = 'x'.freeze\nend\n")

      expect { board.record! }.to raise_error(
        described_class::RefusedError, /debt increased/
      )
    end

    it "records with the override, then clears the marker on the next run" do
      board.record!
      write("second.rb", "module Fixture\n  Y = 'x'.freeze\nend\n")

      ENV["SIRENA_LINT_DEBT_ALLOW_INCREASE"] = "1"
      board.record!
      ENV.delete("SIRENA_LINT_DEBT_ALLOW_INCREASE")

      expect(File.read(File.join(board.directory, "_meta.yml"))).to include(
        "recorded_with_override: true",
      )

      board.record!

      expect(File.read(File.join(board.directory, "_meta.yml"))).to include(
        "recorded_with_override: false",
      )
    end

    it "prunes a cop file whose rows dropped to zero" do
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

      cop_file = File.join(
        board.directory, "Style-FrozenStringLiteralComment.yml"
      )
      expect(File.exist?(cop_file)).to be(false)
    end
  end

  describe "#diff" do
    it "is clean when nothing changed" do
      board.record!
      expect(board.diff).to be_clean
    end

    it "flags a suppressed offence seeded via the todo file (route A)" do
      board.record!
      write("seed_a.rb", "module Fixture\n  Y = 'seed_a'.freeze\nend\n")
      todo = File.read(File.join(root, ".rubocop_todo.yml"))
      write(
        ".rubocop_todo.yml",
        "#{todo}Style/FrozenStringLiteralComment:\n  " \
        "Exclude:\n    - seed_a.rb\n",
      )

      diff = board.diff
      expect(diff).not_to be_clean
      expect(diff.added).to include(
        ["Style/FrozenStringLiteralComment", "seed_a.rb"],
      )
    end

    it "flags a suppressed offence seeded via a fresh Exclude (route B)" do
      board.record!
      write("seed_b.rb", "module Fixture\n  Y = 'seed_b'.freeze\nend\n")
      write(
        ".rubocop.yml",
        "inherit_from:\n  - .rubocop_todo.yml\nAllCops:\n  NewCops: enable\n" \
        "Style/FrozenStringLiteralComment:\n  Exclude:\n    - seed_b.rb\n",
      )

      diff = board.diff
      expect(diff).not_to be_clean
      expect(diff.added).to include(
        ["Style/FrozenStringLiteralComment", "seed_b.rb"],
      )
    end

    it "flags a suppressed offence seeded via an inline directive (route C)" do
      board.record!
      write(
        "seed_c.rb",
        "# frozen_string_literal: true\n\n" \
        "module Fixture\n  " \
        "Y = 1+1 " \
        "# rubocop:disable Layout/SpaceAroundOperators\n" \
        "end\n",
      )

      diff = board.diff
      expect(diff).not_to be_clean
      expect(diff.added).to include(
        ["Layout/SpaceAroundOperators", "seed_c.rb"],
      )
    end
  end
end
