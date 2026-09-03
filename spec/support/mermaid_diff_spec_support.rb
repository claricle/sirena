# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'stringio'
require 'timeout'
require 'tmpdir'

module MermaidDiffSpecSupport
  module Helpers
    # Longer than any example here needs, so a regression that hangs fails the
    # example instead of stalling the suite.
    def guard
      5
    end

    def trivial_source
      "flowchart LR\n  A --> B\n"
    end

    def run_harness(source, *options, mmdc: accepting_mmdc, relative: false)
      Dir.mktmpdir do |dir|
        probe = File.join(dir, 'probe.txt')
        File.write(probe, source)
        bin = fake_mmdc(dir, mmdc)
        script = if relative
                   './scripts/mermaid_diff.rb'
                 else
                   File.expand_path('../../scripts/mermaid_diff.rb', __dir__)
                 end
        command = if relative
                    ['bundle', 'exec', script, *options, probe]
                  else
                    [RbConfig.ruby, script, *options, probe]
                  end
        capture = proc do
          Open3.capture3(
            { 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" },
            *command
          )
        end

        if relative
          Dir.chdir(File.expand_path('../..', __dir__), &capture)
        else
          capture.call
        end
      end
    end

    def oracle_verdict(svg)
      MmdcOracle.verdict('probe') do |_input, output|
        File.write(output, svg)
        [true, '']
      end.verdict
    end

    def intentional_error_svg
      '<svg aria-roledescription="error"><style>.error-icon{fill:#552222;}</style></svg>'
    end

    def syntax_error_svg
      '<svg aria-roledescription="error">' \
        '<style xmlns="http://www.w3.org/1999/xhtml">.error-icon{fill:#552222;}</style></svg>'
    end

    # Runs one probe with mmdc gone, swallowing the note it prints about it.
    def failing_verdict
      capture_stderr { harness.send(:mermaid_verdict, trivial_source) }
    end

    def capture_stderr
      old = $stderr
      $stderr = StringIO.new
      yield
    ensure
      $stderr = old
    end

    # Every descriptor this process holds. /dev/fd lists them on both macOS and
    # Linux, and the reading itself costs the same on either side of a count.
    def open_descriptors
      Dir.children('/dev/fd').size
    end

    def dies?(pid)
      settles { alive?(pid) }
    end

    # A real `ps` that answers slowly, so the window between the last poll and
    # the kill is wide enough to land in on purpose rather than by luck.
    def slow_ps
      "#!/bin/sh\n/bin/sleep 0.8\nexec /bin/ps \"$@\"\n"
    end

    # A program that starts, leaves a child behind, and then never answers.
    # Every caller passes its own sleep duration, so the process table can be
    # searched for exactly its processes and no example sees another's.
    def wedge(seconds)
      "#!/bin/sh\n/bin/sleep #{seconds} &\nexec /bin/sleep #{seconds}\n"
    end

    def gone?(seconds)
      settles { `/bin/ps -eo command=`.include?("sleep #{seconds}") }
    end

    # SIGKILL lands asynchronously and a killed process stays in the table until
    # someone reaps it, so reading the table the instant the signal goes out
    # reports a process that is already on its way down as still there.
    def settles
      Timeout.timeout(guard) { sleep 0.02 while yield }
      true
    rescue Timeout::Error
      false
    end

    def records_in(text)
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'probe.txt')
        File.binwrite(path, text)
        harness.send(:probes, [path])
      end
    end

    # A parent in a process group of its own whose child sits in yet another —
    # the shape puppeteer gives mmdc and Chromium. Built with fork because
    # execing a fresh ruby costs seconds on a cold gem path.
    def spawn_tree
      Dir.mktmpdir do |dir|
        pidfile = File.join(dir, 'child.pid')
        parent = fork do
          Process.setpgid(0, 0)
          File.write(pidfile, Process.spawn('sleep', '120', pgroup: true))
          sleep 120
        ensure
          exit!(0)
        end
        spawned << parent
        child = await_pid(pidfile)
        spawned << child
        [own_group_leader(parent), child]
      end
    end

    def await_pid(pidfile)
      Timeout.timeout(guard) do
        sleep 0.01 until File.exist?(pidfile) && File.read(pidfile).match?(/\A\d+\z/)
      end
      File.read(pidfile).to_i
    end

    # The fork writes its pidfile only once it has its own group, so this holds
    # by the time the examples run. It is checked because kill_group signals a
    # whole group: a parent still in ours would take the suite down with it.
    def own_group_leader(pid)
      raise "pid #{pid} is not its own process group leader" unless Process.getpgid(pid) == pid

      pid
    end

    # Runs a fake mmdc that leaves a child holding the pipe it inherited, then
    # exits. With escape:, that child moves into a process group of its own the
    # way puppeteer starts Chromium; without it, it stays in mmdc's group.
    def run_fake_mmdc(dir, pidfile, escape:)
      script = escape ? escaping_child(pidfile) : child_in_the_group(pidfile)

      prefix_path(fake_mmdc(dir, script)) do
        Timeout.timeout(guard) do
          harness.send(:run_mmdc, File.join(dir, 'in.mmd'), File.join(dir, 'out.svg'))
        end
      end
    end

    # Puts one shell script on PATH under the name mmdc and hands back the
    # directory to prepend.
    def fake_mmdc(dir, script)
      bin = File.join(dir, 'bin')
      Dir.mkdir(bin)
      File.write(File.join(bin, 'mmdc'), script)
      File.chmod(0o755, File.join(bin, 'mmdc'))
      bin
    end

    def rejecting_probe_mmdc
      <<~'SH'
        #!/bin/sh
        if /usr/bin/grep -q '^flowchart LR$' "$2"; then
          printf '%s\n' '<svg aria-roledescription="flowchart-v2"><style/></svg>' > "$4"
          exit 0
        fi
        printf '%s\n' 'syntax error' >&2
        exit 1
      SH
    end

    def broken_browser_mmdc
      <<~'SH'
        #!/bin/sh
        printf '%s\n' 'browser launch failed' >&2
        exit 1
      SH
    end

    def copying_mmdc
      <<~SH
        #!/bin/sh
        /bin/cp "$2" "$4"
      SH
    end

    def accepting_mmdc
      <<~'SH'
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          printf '%s\n' '11.12.0'
          exit 0
        fi
        printf '%s\n' '<svg aria-roledescription="flowchart-v2"><style/></svg>' > "$4"
      SH
    end

    def selective_mmdc
      <<~'SH'
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          printf '%s\n' '11.12.0'
          exit 0
        fi
        if /usr/bin/grep -q 'reject-by-fake' "$2"; then
          printf '%s\n' '<svg aria-roledescription="error"><style xmlns="http://www.w3.org/1999/xhtml"/></svg>' > "$4"
        else
          printf '%s\n' '<svg aria-roledescription="flowchart-v2"><style/></svg>' > "$4"
        fi
      SH
    end

    def unavailable_mmdc
      <<~'SH'
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          printf '%s\n' '11.12.0'
          exit 0
        fi
        printf '%s\n' 'browser launch failed'
        exit 1
      SH
    end

    def corpus_verdict_mmdc
      <<~SH
        #!/bin/sh
        case "$2" in
          *accept.mmd|*reject.mmd) /bin/cp "$2" "$4" ;;
          *) exit 1 ;;
        esac
      SH
    end

    def rejecting_corpus_mmdc
      <<~'SH'
        #!/bin/sh
        printf '%s\n' 'UnknownDiagramError: no diagram type detected' >&2
        exit 1
      SH
    end

    def version_mmdc(version)
      "#!/bin/sh\nprintf '%s\\n' '#{version}'\n"
    end

    # The child writes its pid only once it has left the group, and mmdc waits
    # for that, so the escape has always happened by the time mmdc exits. It
    # used to race the group kill and usually lose, and the example passed
    # without ever testing an escaped child.
    def escaping_child(pidfile)
      perl = %q(perl -e 'setpgrp(0,0); open(F, ">", $ARGV[0]) or die; ) +
             %q(print F $$; close F; exec("/bin/sleep", "20.29")')
      "#!/bin/sh\n#{perl} '#{pidfile}' &\n" \
        "while [ ! -s '#{pidfile}' ]; do sleep 0.01; done\n" \
        "sleep 0.1\n"
    end

    def child_in_the_group(pidfile)
      "#!/bin/sh\n/bin/sleep 20.29 &\necho $! > '#{pidfile}'\n"
    end

    def interruptible_mmdc(pidfile)
      "#!/bin/sh\necho $$ > '#{pidfile}'\nexec /bin/sleep 20.71\n"
    end

    # PATH becomes this one directory, so the real program cannot be reached.
    # A nil script leaves the directory empty — the program is simply gone.
    def only(program, script, &block)
      Dir.mktmpdir do |dir|
        if script
          File.write(File.join(dir, program), script)
          File.chmod(0o755, File.join(dir, program))
        end
        with_path(dir, &block)
      end
    end

    def prefix_path(dir, &)
      with_path("#{dir}:#{ENV.fetch('PATH')}", &)
    end

    def with_path(path)
      old = ENV.fetch('PATH')
      ENV['PATH'] = path
      yield
    ensure
      ENV['PATH'] = old
    end

    def alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def kill_quietly(pid)
      Process.kill('KILL', pid)
    rescue Errno::ESRCH
      nil
    ensure
      begin
        Process.waitpid(pid, Process::WNOHANG)
      rescue Errno::ECHILD
        nil
      end
    end
  end
end
