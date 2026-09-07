# frozen_string_literal: true

require 'timeout'

# Spawns mmdc the way its Chromium-backed process tree actually requires:
# its own process group, a deadline, and a sweep for children that escape
# the group. Two call sites need this — the differential harness and the
# corpus verifier — and both hang the same way if it is skipped: measured at
# one escaped Chromium holding a 30s case open for 301.7s.
module HardenedMmdc
  module_function

  # Sirena gets the same deadline mmdc has here, so a caller comparing the two
  # is comparing them under one shared budget rather than two independent
  # guesses.
  CASE_TIMEOUT = 30

  # `ps` is a separate program and it can wedge. A process table prints in
  # milliseconds, so five seconds means it is never coming.
  PS_TIMEOUT = 5

  # How long to wait for the pipe once mmdc is gone. Only a process that
  # escaped the kill still holds the write end, and it will not let go.
  DRAIN_GRACE = 1

  # Its own process group, so a hung Chromium goes down with it rather than
  # outliving the deadline.
  #
  # The output is drained on a thread while we wait. Reading it afterwards
  # deadlocked: a probe emitting 80KB of KaTeX warnings filled the 64KB pipe,
  # mmdc blocked writing, and a diagram it renders was reported MMDC FAILED
  # on the deadline.
  #
  # The ensure clause kills the tree as well as closing the pipe, or a SIGINT
  # left mmdc and its Chromium children running after the harness exited.
  #
  # The group goes down on every path, not just the deadline. A child that
  # stayed in it used to outlive a normally-exiting mmdc, and one of those
  # accumulated per case.
  #
  # The wait on the drain is bounded because the group kill does not reach a
  # child that left the group — Chromium does exactly that. Such a child still
  # holds the pipe's write end, so reading to EOF waited on THAT process: one
  # escaped Chromium held a 30s case open for 301.7s.
  #
  # The pipe is opened with a block so both ends close however we leave. They
  # used to be closed by hand after the spawn, so a spawn that raised leaked
  # the write end — measured at one descriptor per failure, 20 for 20.
  def run_mmdc(input, output)
    IO.pipe do |stdout_r, stdout_w|
      pid = Process.spawn('mmdc', '-i', input, '-o', output,
                          out: stdout_w, err: stdout_w, pgroup: true)
      stdout_w.close
      drain = Thread.new { stdout_r.read }

      descendants = descendants_of(pid)
      status = wait_with_deadline(pid, descendants: descendants)
      kill_group_id(pid)
      [status, drain.join(DRAIN_GRACE) ? drain.value : '']
    ensure
      kill_group(pid) if pid && status.nil?
      kill_each(descendants || [])
      drain&.kill
    end
  end

  def wait_with_deadline(pid, descendants: nil)
    deadline = monotonic + CASE_TIMEOUT

    loop do
      if descendants
        descendants.concat(descendants_of(pid))
        descendants.uniq!
      end

      finished, status = Process.waitpid2(pid, Process::WNOHANG)
      return status if finished
      return kill_group(pid) if monotonic > deadline

      sleep 0.05
    end
  end

  # Killing mmdc's process group is not enough: puppeteer starts Chromium in
  # a group of its own, and after the group kill it survived under PID 1 for
  # seconds. The descendants have to be collected BEFORE the kill, because
  # once the parent dies they are reparented and the trail is gone. A first
  # snapshot is taken immediately after spawn and repeated while the leader is
  # alive, so a child that escapes a normally exiting mmdc is still collected.
  #
  # Collecting the descendants means running `ps`, and mmdc can finish while
  # that runs. The status it finished with is the verdict we came for, so it
  # is handed back rather than thrown away — one that exited 7 in this window
  # was reported as MMDC FAILED, for a source mermaid had a real answer to.
  #
  # ECHILD is the second pass over a case that timed out: the deadline already
  # reaped mmdc here, and then `run_mmdc` cleans up again on the way out
  # because it has no status. There is nothing left to wait for by then.
  def kill_group(pid)
    doomed = descendants_of(pid)
    kill_group_id(pid)
    status = status_unless_killed(pid)
    kill_each(doomed)
    status
  rescue Errno::ECHILD
    kill_each(doomed)
    nil
  end

  # What the program ended with, unless the KILL we just sent is what ended
  # it: a program we killed never got to answer, and saying it exited nonzero
  # would read as mermaid rejecting the source.
  def status_unless_killed(pid)
    _, status = Process.waitpid2(pid)
    status.termsig == Signal.list.fetch('KILL') ? nil : status
  end

  # Programs are spawned into a process group of their own, so a group's id is
  # the program's pid. That still holds once the program has been reaped, which
  # is why a group can be cleaned up on the way out.
  #
  # EPERM here means the same as ESRCH: nothing is left that can be signalled.
  # Measured — a live leader with a live child signals fine and the child dies,
  # a reaped leader gives ESRCH, and a leader that is still an unreaped zombie
  # gives EPERM.
  def kill_group_id(pid)
    Process.kill('KILL', -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def kill_each(pids)
    pids.each do |child|
      Process.kill('KILL', child)
    rescue Errno::ESRCH
      nil
    end
  end

  # The sweep asks another program for the process table, and that program can
  # fail us: a sandbox refuses the exec, a wedged one never answers, a garbled
  # one breaks the parse. Any of those used to raise or block right here, and
  # the caller never reached its kill. Losing the descendants is survivable;
  # losing the group kill is not.
  def descendants_of(pid)
    subtree_of(pid)
  rescue StandardError
    []
  end

  # The whole subtree, from one `ps` snapshot.
  def subtree_of(pid)
    parents = Hash.new { |hash, key| hash[key] = [] }
    capture(['ps', '-eo', 'pid=,ppid='], PS_TIMEOUT).each_line do |line|
      child, parent = line.split.map { |field| Integer(field, exception: false) }
      parents[parent] << child if child&.positive? && parent&.positive?
    end

    found = []
    queue = [pid]
    until queue.empty?
      current = queue.shift
      parents[current].each do |child|
        next if found.include?(child)

        found << child
        queue << child
      end
    end
    found
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Runs a program and hands back what it printed. Spawned rather than
  # backticked so that one which never answers can be killed: a descendant can
  # inherit the capture pipe's write end, so leaving it running keeps `io.read`
  # from reaching EOF. Measured with a wedged `ps` — the sweep came back in
  # 0.30s and the reader waited 21.29s for EOF.
  def capture(command, timeout)
    io = IO.popen(command, err: File::NULL, pgroup: true)
    begin
      Timeout.timeout(timeout) { io.read }
    ensure
      # The whole group, not just the program: a wedged one that had already
      # started a child left that child running. Unconditional, because on the
      # normal path the program is at EOF and already on its way out.
      kill_group_id(io.pid)
      io.close
    end
  end

  # Only run_mmdc and capture are the public entry points the other scripts
  # call. Everything else is an implementation detail of those two — matching
  # the privacy these methods had before the extraction, when they were
  # unqualified top-level defs reachable only via `.send` (per the ORIGINAL
  # top-level scoping in mermaid_diff.rb, before this module existed).
  private_class_method :wait_with_deadline, :kill_group, :status_unless_killed,
                       :kill_group_id, :kill_each, :descendants_of, :subtree_of,
                       :monotonic
end
