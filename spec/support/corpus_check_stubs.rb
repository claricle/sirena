# frozen_string_literal: true

# Drives Sirena::Corpus.check! without the real corpus or committed
# scoreboard. Include in a spec that defines `committed`.
module CorpusCheckStubs
  def stub_fresh_run(passes)
    results = passes.transform_values { |pass| { pass: pass, stage: "parse", exception_class: "X" } }
    allow(described_class).to receive_messages(
      load_scoreboard: committed, cases: results.keys, run_cases: results, verdicts: {}
    )
  end

  # check! aborts with SystemExit; returns its status, or 0 if it returns.
  def exit_status_of
    yield
    0
  rescue SystemExit => e
    e.status
  end
end
