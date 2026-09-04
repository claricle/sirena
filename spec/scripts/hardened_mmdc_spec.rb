# frozen_string_literal: true

require 'timeout'
require 'tmpdir'

require_relative '../support/mermaid_diff_spec_support'

# HardenedMmdc is a real module (not a wrapped script), loaded the ordinary
# way — this file runs standalone, independent of mermaid_diff_spec.rb.
require_relative '../../scripts/hardened_mmdc'

# CorpusVerdicts is a program, not a library, same as MermaidDiff in the
# sibling spec — loaded into its own module so this file does not depend on
# mermaid_diff_spec.rb having run first (or on being run at all in the same
# process), and does not collide with that file's own load of the same
# script when both run together in one suite.
unless defined?(CorpusVerdicts)
  CorpusVerdicts = Module.new
  load File.expand_path('../../scripts/corpus_verdicts.rb', __dir__), CorpusVerdicts
end

# Every process tree uses real processes — a stub would only prove that the
# rescue matches what the stub was told to raise.
RSpec.describe HardenedMmdc do
  include MermaidDiffSpecSupport::Helpers

  let(:spawned) { [] }

  before { skip('the harness is POSIX-only') if Gem.win_platform? }

  after { spawned.each { |pid| kill_quietly(pid) } }

  # Explains why kill_group is exercised through a process tree it did not
  # spawn itself: a `fork`-based tree cannot go through Process.spawn's
  # `pgroup:` option without an intervening exec, so the tree is built by hand
  # and handed to the method under test.
  describe 'the descendant sweep' do
    {
      'is not on PATH at all' => nil,
      'never answers' => "#!/bin/sh\nexec /bin/sleep 30 2>/dev/null\n",
      'prints bytes that are not UTF-8' => "#!/bin/sh\nprintf '\\377\\376 1 0\\n'\n"
    }.each do |trouble, script|
      it "kills the group anyway when ps #{trouble}" do
        stub_const('HardenedMmdc::PS_TIMEOUT', 0.3)
        parent, _child = spawn_tree

        only('ps', script) { Timeout.timeout(guard) { described_class.send(:kill_group, parent) } }

        expect(dies?(parent)).to be(true)
      end
    end

    it 'kills a descendant that sits in a process group of its own' do
      parent, child = spawn_tree

      Timeout.timeout(guard) { described_class.send(:kill_group, parent) }

      expect(dies?(child)).to be(true)
    end

    it 'keeps malformed and nonpositive pids out of the descendant list' do
      pid = Process.pid
      table = "#!/bin/sh\nprintf '%s\\n' 'garbled #{pid}' '7garbled #{pid}' " \
              "'0 #{pid}' '-7 #{pid}' '8 #{pid}garbled' '9 0' '10 -7'\n"

      descendants = only('ps', table) { described_class.send(:subtree_of, pid) }

      expect(descendants).to eq([])
    end

    # Giving up on a wedged `ps` is not enough. A descendant can inherit the
    # capture pipe's write end, so leaving it running keeps the read from EOF:
    # measured, the sweep returned in 0.30s and the reader waited 21.29s.
    it 'kills a ps that never answers rather than leave its pipe open' do
      stub_const('HardenedMmdc::PS_TIMEOUT', 1)

      only('ps', wedge('20.17')) do
        Timeout.timeout(guard) { described_class.send(:descendants_of, Process.pid) }
      end

      expect(gone?('20.17')).to be(true)
    end
  end

  # The deadline is not the only thing that can be true when cleanup runs.
  # Collecting descendants means waiting on `ps`, and mmdc can finish while
  # that happens.
  describe 'waiting out the deadline' do
    it 'keeps the status of a program that finished while ps was running' do
      stub_const('HardenedMmdc::CASE_TIMEOUT', 0)
      pid = Process.spawn('/bin/sh', '-c', 'sleep 0.4; exit 7', pgroup: true)
      spawned << pid

      status = only('ps', slow_ps) { Timeout.timeout(guard) { described_class.send(:wait_with_deadline, pid) } }

      expect(status.exitstatus).to eq(7)
    end

    # The complement: a program the deadline really did kill has no verdict,
    # and handing back its status would read as mermaid rejecting the source.
    it 'gives no status for a program the deadline killed' do
      stub_const('HardenedMmdc::CASE_TIMEOUT', 0)
      pid = Process.spawn('/bin/sh', '-c', 'sleep 20.61', pgroup: true)
      spawned << pid

      status = Timeout.timeout(guard) { described_class.send(:wait_with_deadline, pid) }

      expect(status).to be_nil
    end

    # A case that times out is cleaned up twice: the deadline reaps mmdc, and
    # then run_mmdc cleans up again because it came away with no status. The
    # second pass has nothing left to wait for, and it used to raise
    # Errno::ECHILD straight out of the harness on every case that timed out.
    it 'cleans up twice after a case that timed out without raising' do
      stub_const('HardenedMmdc::CASE_TIMEOUT', 0.3)

      status, output = Dir.mktmpdir do |dir|
        prefix_path(fake_mmdc(dir, "#!/bin/sh\nexec /bin/sleep 26.43\n")) do
          Timeout.timeout(guard) do
            described_class.run_mmdc(File.join(dir, 'in.mmd'), File.join(dir, 'out.svg'))
          end
        end
      end

      expect(status).to be_nil
      expect(output).to eq('')
      expect(gone?('26.43')).to be(true)
    end
  end

  describe 'cleaning up after mmdc' do
    it 'kills a child that stayed in the group mmdc was given' do
      Dir.mktmpdir do |dir|
        pidfile = File.join(dir, 'child.pid')

        run_fake_mmdc(dir, pidfile, escape: false)

        expect(dies?(File.read(pidfile).to_i)).to be(true)
      end
    end

    # A child that leaves the group is out of reach of the kill and still
    # holds the pipe, so reading to EOF waits on IT: one escaped Chromium
    # held a 30s case open for 301.7s.
    it 'stops waiting on the pipe when a child escapes the group' do
      stub_const('HardenedMmdc::DRAIN_GRACE', 0.3)

      Dir.mktmpdir do |dir|
        pidfile = File.join(dir, 'child.pid')

        status, output = run_fake_mmdc(dir, pidfile, escape: true)

        expect(status).to be_success
        expect(output).to eq('')
        expect(dies?(File.read(pidfile).to_i)).to be(true)
      ensure
        kill_quietly(File.read(pidfile).to_i) if File.size?(pidfile)
      end
    end

    it 'passes source bytes to mmdc unchanged' do
      Dir.mktmpdir do |dir|
        input = File.join(dir, 'in.mmd')
        output = File.join(dir, 'out.svg')
        source = "flowchart LR\n  A[\xFF\xFE]\n".b
        File.binwrite(input, source)

        prefix_path(fake_mmdc(dir, <<~SH)) do
          #!/bin/sh
          /bin/cp "$2" "$4"
        SH
          status, = described_class.run_mmdc(input, output)

          expect(status).to be_success
          expect(File.binread(output)).to eq(source)
        end
      end
    end

    it 'drains a large mmdc diagnostic while it runs' do
      Dir.mktmpdir do |dir|
        input = File.join(dir, 'in.mmd')
        output = File.join(dir, 'out.svg')
        File.write(input, trivial_source)

        prefix_path(fake_mmdc(dir, <<~SH)) do
          #!/bin/sh
          perl -e 'print "x" x 100000'
        SH
          status, diagnostic = described_class.run_mmdc(input, output)

          expect(status).to be_success
          expect(diagnostic).to eq('x' * 100_000)
        end
      end
    end

    it 'cleans up when interrupted' do
      Dir.mktmpdir do |dir|
        input = File.join(dir, 'in.mmd')
        output = File.join(dir, 'out.svg')
        pidfile = File.join(dir, 'mmdc.pid')
        File.write(input, trivial_source)

        prefix_path(fake_mmdc(dir, interruptible_mmdc(pidfile))) do
          wait_for_pid = proc do
            Timeout.timeout(guard) { sleep 0.01 until File.exist?(pidfile) }
          end
          original_descendants_of = described_class.method(:descendants_of)
          allow(described_class).to receive(:descendants_of) do |pid|
            result = original_descendants_of.call(pid)
            wait_for_pid.call
            result
          end
          allow(described_class).to receive(:wait_with_deadline).and_raise(Interrupt)

          expect { described_class.run_mmdc(input, output) }.to raise_error(Interrupt)
          pid = File.read(pidfile).to_i
          expect(dies?(pid)).to be(true)
        ensure
          kill_quietly(pid) if pid
        end
      end
    end
  end

  # HardenedMmdc's whole reason to exist: corpus_verdicts.rb used to call
  # mmdc through a bare Open3.capture3 with no timeout, and a hung mmdc never
  # returned. Measured directly, not argued: pointed local_mmdc_verdict at a
  # fake mmdc that only sleeps, and it hung until an external `timeout`
  # intervened, because nothing inside the call would stop it.
  describe 'protecting a second call site the same way' do
    let(:corpus_harness) { Class.new { include CorpusVerdicts }.new }

    it 'kills a hanging mmdc reached through corpus_verdicts.rb, not just mermaid_diff.rb' do
      stub_const('HardenedMmdc::CASE_TIMEOUT', 0.3)

      Dir.mktmpdir do |dir|
        input = File.join(dir, 'in.mmd')
        File.write(input, trivial_source)

        prefix_path(fake_mmdc(dir, "#!/bin/sh\nexec /bin/sleep 26.83\n")) do
          verdict = Timeout.timeout(guard) do
            corpus_harness.send(:local_mmdc_verdict, input)
          end

          expect(verdict).to be(:error)
          expect(gone?('26.83')).to be(true)
        end
      end
    end
  end
end
