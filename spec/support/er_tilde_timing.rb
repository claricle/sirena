# frozen_string_literal: true

# Times an er_diagram tilde-type parse for a given non-tilde run length,
# asserting the parsed attribute type is correct so a broken/empty parse
# can't pass on speed alone. Returns the MINIMUM elapsed time over several
# attempts, and uses CPU time (not wall-clock) -- both choices exist to
# survive scheduler noise on a shared machine without false-reding the
# fixed grammar or false-greening a reverted one. See the gate record for
# the measurements that picked these.
module ErTildeTiming
  # How much slower a 16x-larger run is allowed to parse. Sits with
  # headroom above the O(n) grammar's measured ratio and well below the
  # O(n^2) grammar's -- see the gate record for the raw numbers this was
  # picked from.
  MAX_LINEAR_SCALING_RATIO = 30

  def min_tilde_parse_time(char_count, attempts: 3, position: :prefix)
    Array.new(attempts) { time_tilde_parse(char_count, position: position) }.min
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

    start = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    diagram = parser.parse(source)
    elapsed = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - start

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
    Array.new(attempts) { time_tilde_pair_parse(pair_count) }.min
  end

  def time_tilde_pair_parse(pair_count)
    type = Array.new(pair_count) { |i| "~a#{i}~" }.join
    source = "erDiagram\n  ENTITY {\n    #{type} rental_date\n  }\n"

    start = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    diagram = parser.parse(source)
    elapsed = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - start

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
end
