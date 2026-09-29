# frozen_string_literal: true

# Times an er_diagram tilde-type or note parse for a given input size,
# asserting the parsed result is correct so a broken/empty parse can't pass
# on speed alone. Returns the MINIMUM elapsed time over several attempts,
# and uses CPU time (not wall-clock) -- both choices exist to survive
# scheduler noise on a shared machine without false-reding the fixed
# grammar or false-greening a reverted one. See the gate record for the
# measurements that picked these.
module ErTildeTiming
  # How much slower a 16x-larger run is allowed to parse. Sits with
  # headroom above the O(n) grammar's measured ratio and well below the
  # O(n^2) grammar's -- see the gate record for the raw numbers this was
  # picked from.
  MAX_LINEAR_SCALING_RATIO = 30

  # A single small-input parse can be a few CPU milliseconds -- on
  # windows-latest CI, Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID)
  # comes from GetProcessTimes, which only advances on a ~15.6ms scheduler
  # tick, so one call often reads exactly 0.0 and turns the scaling ratio
  # into Infinity or NaN. Repeating the parse until the ACCUMULATED time
  # clears this floor, then averaging, keeps every sample a real
  # multi-tick measurement regardless of how fast a single call is.
  MIN_SAMPLE_SECONDS = 0.05

  # A pathological per-call timer (stuck at exactly 0.0 forever) would
  # otherwise loop without bound; this caps it into a clear failure
  # instead of a hung suite.
  MAX_SAMPLE_ITERATIONS = 20_000

  def min_tilde_parse_time(char_count, attempts: 3, position: :prefix)
    Array.new(attempts) { average_call_time { time_tilde_parse(char_count, position: position) } }.min
  end

  # Ratio of parse time at `large` chars over parse time at `small`
  # chars. An O(n) rule scales roughly with the size ratio; an O(n^2)
  # rule scales roughly with its square, which is what makes this ratio
  # -- not an absolute duration -- the thing worth asserting: it stays
  # discriminating regardless of how fast or loaded the machine is.
  def tilde_parse_scaling_ratio(small, large, position: :prefix, attempts: 5)
    small_time = min_tilde_parse_time(small, attempts: attempts, position: position)
    large_time = min_tilde_parse_time(large, attempts: attempts, position: position)
    large_time / small_time
  end

  # position: :prefix stresses tilde_prefix with the long run (before the
  # opening tilde), :suffix stresses tilde_suffix (after the closing
  # tilde) -- the two rules were fixed together but are independent
  # Parslet rules, so a regression that reverted only one of them needs
  # a long run on each side to be caught.
  def time_tilde_parse(char_count, position: :prefix)
    long_run = 'a' * char_count
    body = position == :prefix ? "#{long_run}~foo bar~x" : "foo~bar baz~#{long_run}"
    source = "erDiagram\n  ENTITY {\n    #{body} rental_date\n  }\n"

    diagram = nil
    elapsed = cpu_time { diagram = parser.parse(source) }

    attr = diagram.find_entity('ENTITY').attributes.first
    # `body` has 2 tildes, so `extract_attribute_type` pairs them into
    # `<`/`>` (mermaid's own display convention) rather than leaving them
    # be -- assert on that, not the raw tilde text, so this stays a
    # correctness check and not just a speed check.
    expect(attr.attribute_type).to eq(body.sub('~', '<').sub('~', '>'))
    elapsed
  end

  # Ratio of parse time at `large` PAIRS of adjacent tildes over `small`
  # pairs, all inside ONE attribute type (no whitespace between pairs, so
  # `tilde_type` captures them as a single run). Stresses
  # `process_tilde_set` (`builders/er_diagram.rb`), a different code path
  # from `tilde_prefix`/`tilde_suffix` above -- a many-tilde type like
  # mermaid's own generics chains.
  def tilde_pair_count_scaling_ratio(small, large, attempts: 3)
    small_time = min_tilde_pair_parse_time(small, attempts: attempts)
    large_time = min_tilde_pair_parse_time(large, attempts: attempts)
    large_time / small_time
  end

  def min_tilde_pair_parse_time(pair_count, attempts: 3)
    Array.new(attempts) { average_call_time { time_tilde_pair_parse(pair_count) } }.min
  end

  def time_tilde_pair_parse(pair_count)
    type = Array.new(pair_count) { |i| "~a#{i}~" }.join
    source = "erDiagram\n  ENTITY {\n    #{type} rental_date\n  }\n"

    diagram = nil
    elapsed = cpu_time { diagram = parser.parse(source) }

    attr = diagram.find_entity('ENTITY').attributes.first
    # Outside-in pairing (first tilde with last, second with
    # second-to-last, ...) means the result is NOT simply `<a0><a1>...` --
    # assert on the invariant that stays true regardless of pairing order:
    # every tilde became exactly one `<` or `>`, none survive.
    expect(attr.attribute_type).not_to include('~')
    expect(attr.attribute_type.count('<')).to eq(pair_count)
    expect(attr.attribute_type.count('>')).to eq(pair_count)
    elapsed
  end

  # Ratio of parse time at `large` chars of a quoted note over `small`
  # chars. Stresses the ER `note` grammar rule (`grammars/er_diagram.rb`),
  # a different rule from the tilde ones above -- a native
  # `match(...).repeat` there would fold one-char Slices back together
  # with `Slice#+`, which is O(n^2) to scan a single long note.
  def note_parse_scaling_ratio(small, large, attempts: 5)
    small_time = min_note_parse_time(small, attempts: attempts)
    large_time = min_note_parse_time(large, attempts: attempts)
    large_time / small_time
  end

  def min_note_parse_time(char_count, attempts: 3)
    Array.new(attempts) { average_call_time { time_note_parse(char_count) } }.min
  end

  def time_note_parse(char_count)
    note = 'n' * char_count
    source = "erDiagram\n  ENTITY {\n    int id PK \"#{note}\"\n  }\n"

    diagram = nil
    elapsed = cpu_time { diagram = parser.parse(source) }

    attr = diagram.find_entity('ENTITY').attributes.first
    expect(attr.note).to eq(note)
    elapsed
  end

  # Minimum CPU time over `attempts` calls of an arbitrary block (not
  # tied to a specific `time_*` shape above) -- used for scaling specs
  # that time a whole `parser.parse` call directly.
  def min_call_time(attempts: 3, &block)
    Array.new(attempts) { average_call_time(&block) }.min
  end

  # A full ER diagram with `count` attributes, each with its own short
  # tilde-quoted type -- stresses `tilde_prefix`/`tilde_suffix` called
  # once PER ATTRIBUTE, the shape a fixed-size chunk regresses on (many
  # short calls, not one long run).
  def many_tilde_attributes(count)
    attrs = Array.new(count) { |i| "    ~t#{i}~ attr#{i}" }.join("\n")
    "erDiagram\n  ENTITY {\n#{attrs}\n  }\n"
  end

  private

  def cpu_time
    start = Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID)
    yield
    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID) - start
  end

  # Repeats `block` (a `time_*` method above: it both asserts correctness
  # and returns one call's elapsed CPU time) until the SUM clears
  # MIN_SAMPLE_SECONDS, then returns the average -- see the constant's
  # comment for why a single call's reading can't be trusted directly.
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
