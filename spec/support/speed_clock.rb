# frozen_string_literal: true

# The one way a spec reads the wall clock. Both it and CpuTiming#cpu_time
# raise unless the running example is tagged :speed, so a timed assertion
# always gets the single re-run in spec/support/speed_retry.rb.
module SpeedClock
  def self.require_speed_tag!
    example = RSpec.current_example
    return if example && example.metadata[:speed]

    raise "tag this example :speed: it reads the clock " \
          "(spec/support/speed_retry.rb)"
  end

  # Seconds the block took, by the monotonic clock.
  def wall_time
    SpeedClock.require_speed_tag!
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end
end

RSpec.configure { |config| config.include SpeedClock }
