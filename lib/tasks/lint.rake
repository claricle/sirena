# frozen_string_literal: true

# Card step 3's emitter: sirena's suppressed rubocop debt, measured
# against a synthesised config so no local `.rubocop.yml` key can hide
# it, then checked into scoreboard/lint-debt/ as the ratchet's baseline.
#
# `lint:debt`        prints the current measurement as JSON.
# `lint:debt:record` writes it into the scoreboard, refusing to widen
#                     debt unless SIRENA_LINT_DEBT_ALLOW_INCREASE=1.
# `lint:debt:check`  fails when the working tree no longer matches what
#                     is checked in -- this is the guard card step 4
#                     seeds three suppressed offences against.

desc "Print sirena's suppressed rubocop debt as JSON"
task "lint:debt" do
  require "sirena/lint_debt"
  require "json"

  root = File.expand_path("../..", __dir__)
  debt = Sirena::LintDebt.new(root: root)
  puts JSON.pretty_generate(debt.report)
rescue Sirena::LintDebt::ExecutionError => e
  warn "lint:debt failed: #{e.message}"
  exit 1
end

desc "Write the current debt rows into scoreboard/lint-debt/"
task "lint:debt:record" do
  require "sirena/lint_debt"
  require "sirena/lint_debt_scoreboard"

  root = File.expand_path("../..", __dir__)
  debt = Sirena::LintDebt.new(root: root)
  board = Sirena::LintDebtScoreboard.new(root: root, debt: debt)
  summary = board.record!

  note = summary[:bootstrap] ? " (bootstrap)" : ""
  puts "lint:debt:record — #{summary[:cops_written]} cop files, " \
       "#{summary[:total]} total debt#{note}"
rescue Sirena::LintDebt::ExecutionError,
       Sirena::LintDebtScoreboard::RefusedError => e
  warn "lint:debt:record failed: #{e.message}"
  exit 1
end

desc "Compare current debt rows to the checked-in scoreboard"
task "lint:debt:check" do
  require "sirena/lint_debt"
  require "sirena/lint_debt_scoreboard"

  root = File.expand_path("../..", __dir__)
  debt = Sirena::LintDebt.new(root: root)
  board = Sirena::LintDebtScoreboard.new(root: root, debt: debt)
  diff = board.diff

  if diff.clean?
    puts "lint:debt:check — scoreboard matches (#{debt.total} total debt)"
  else
    warn "lint:debt:check failed — scoreboard does not match:"
    warn diff
    exit 1
  end
rescue Sirena::LintDebt::ExecutionError => e
  warn "lint:debt:check failed: #{e.message}"
  exit 1
end
