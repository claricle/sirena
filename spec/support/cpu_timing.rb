# frozen_string_literal: true

# CPU-time sampling for scaling specs. Assert a RATIO of two timings,
# never an absolute duration: the ratio stays meaningful on a slow or
# loaded machine.
module CpuTiming
  # A single small-input parse can be a few CPU milliseconds -- on
  # windows-latest CI, Process.times comes from GetProcessTimes, which
  # only advances on a ~15.6ms scheduler tick, so one call often reads
  # exactly 0.0 and turns the scaling ratio into Infinity or NaN.
  # Repeating the call until the ACCUMULATED time clears this floor,
  # then averaging, keeps every sample a real multi-tick measurement
  # regardless of how fast a single call is.
  MIN_SAMPLE_SECONDS = 0.05

  # A pathological per-call timer (stuck at exactly 0.0 forever) would
  # otherwise loop without bound; this caps it into a clear failure
  # instead of a hung suite.
  MAX_SAMPLE_ITERATIONS = 20_000

  # Minimum over `attempts` of average_call_time. The block returns one
  # call's elapsed CPU time, e.g. `min_call_time { cpu_time { parse } }`.
  def min_call_time(attempts: 3, &block)
    Array.new(attempts) { average_call_time(&block) }.min
  end

  # Process.times, not clock_gettime: Windows Ruby has no CPU-time clock
  # for clock_gettime and raises Errno::EINVAL.
  def cpu_time
    SpeedClock.require_speed_tag!
    start = Process.times
    yield
    finish = Process.times
    (finish.utime + finish.stime) - (start.utime + start.stime)
  end

  private

  # Repeats the block (which returns one call's elapsed CPU time) until
  # the SUM clears MIN_SAMPLE_SECONDS, then returns the average.
  def average_call_time
    total = 0.0
    calls = 0
    while total < MIN_SAMPLE_SECONDS
      total += yield
      calls += 1
      if calls >= MAX_SAMPLE_ITERATIONS
        raise "timing sample never reached the #{MIN_SAMPLE_SECONDS}s floor " \
              "after #{MAX_SAMPLE_ITERATIONS} calls"
      end
    end
    total / calls
  end
end
