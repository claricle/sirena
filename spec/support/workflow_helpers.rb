# frozen_string_literal: true

# Builders for the workflow-shaped hashes the CI workflow specs feed to scripts/.
module WorkflowHelpers
  def workflow_with(uses)
    { "jobs" => { "j" => { "timeout-minutes" => 1, "steps" => [{ "uses" => uses }] } } }
  end

  def result(name, outcome)
    { name => { "result" => outcome, "outputs" => {} } }
  end
end
