# frozen_string_literal: true

# An example tagged :speed asserts how long something takes, so a busy CI
# runner can fail it with no regression behind it. It gets ONE re-run in the
# same process and is red only when both runs fail. Every other example runs
# exactly once: tag an example :speed only when it reads the clock.
module SpeedRetry
  def self.install(config)
    config.around(:each, :speed) do |example|
      SpeedRetry.refuse_aggregate_failures!(example)
      example.run
      next unless example.exception

      SpeedRetry.announce_rerun(example)
      # Cleared, or the re-run is reported failed whatever it does.
      example.example.instance_variable_set(:@exception, nil)
      # Fresh `let`s, or the re-run would reuse the first run's timings. An
      # instance variable the example body sets is NOT reset.
      __init_memoized
      example.run
    end
  end

  # RSpec's own :aggregate_failures hook wraps the :speed one and holds every
  # failure until it returns, so the re-run would never fire.
  def self.refuse_aggregate_failures!(example)
    return unless example.metadata[:aggregate_failures]

    raise ArgumentError, "a :speed example cannot use :aggregate_failures"
  end

  def self.announce_rerun(example)
    first_line = example.exception.message.strip.lines.first&.strip
    warn "#{example.full_description} failed once, re-running: #{first_line}"
  end
end

RSpec.configure { |config| SpeedRetry.install(config) }
