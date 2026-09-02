# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'rake'
require 'tmpdir'
require 'securerandom'
require 'stringio'
require 'yaml'

# The generation task deletes files. Nothing else in the suite calls it: the
# conformance gate reads what is on disk, so it catches an orphan that already
# shipped and says nothing about whether the sweeper removes one. Disabling the
# sweep left the whole suite green, which is why this exists.
#
# The rake file is loaded rather than reimplemented, so the helpers under test
# are the ones the task runs. Loading it defines tasks into the default Rake
# application; none is invoked here.
TASKS_RAKE_FILE = File.expand_path('../../../lib/tasks/examples.rake', __dir__)
load TASKS_RAKE_FILE unless defined?(ExampleTasks)

RSpec.describe ExampleTasks do
  around do |example|
    Dir.mktmpdir('sirena-examples') do |dir|
      @examples_dir = dir
      example.run
    end
  end

  attr_reader :examples_dir

  def silently
    result = nil
    capture { result = yield }
    result
  end

  def capture
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  # Fails the temporary write half-done while still running write_svg's own
  # block, so the bookkeeping inside it (which decides whether the temporary
  # file is cleaned up) runs exactly as it does in production. Replacing the
  # block instead skipped that, and made a passing spec out of debris the real
  # code would have removed.
  def fail_temporary_write_partway
    original_open = File.method(:open)
    allow(File).to receive(:open) do |path, *arguments, &block|
      next original_open.call(path, *arguments, &block) unless path.to_s.end_with?('.tmp')

      original_open.call(path, *arguments) do |file|
        def file.write(content)
          super(content.to_s[0, 4])
          raise Errno::EFBIG
        end
        block.call(file)
      end
    end
  end

  def write(relative_path, content = 'x')
    path = File.join(examples_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  describe '.prune_orphan_svgs' do
    it 'keeps an SVG whose source is still there' do
      write('flowchart/01-basic.mmd')
      svg = write('flowchart/01-basic.svg')

      described_class.prune_orphan_svgs(examples_dir)

      expect(File).to exist(svg)
    end

    it 'removes an SVG whose source is gone' do
      orphan = write('flowchart/02-deleted.svg')

      expect(described_class.prune_orphan_svgs(examples_dir)).to eq(1)
      expect(File).not_to exist(orphan)
    end

    # The gemspec packages every SVG under examples/ at any depth, so a sweep
    # one level deep leaves exactly the orphans a human then deletes by hand.
    it 'removes an orphan sitting directly under examples' do
      orphan = write('stray_example.svg')

      described_class.prune_orphan_svgs(examples_dir)

      expect(File).not_to exist(orphan)
    end

    it 'leaves files that are not SVGs alone' do
      kept = write('flowchart/notes.txt')

      described_class.prune_orphan_svgs(examples_dir)

      expect(File).to exist(kept)
    end

    # The gemspec packages an SVG beside its source and one directly under
    # examples/; nothing here manages a deeper tree, and a sweep that reached
    # one deleted a fixture it had no claim on.
    it 'leaves a nested tree it does not manage alone' do
      nested = write('deep/nested/fixture.svg')

      described_class.prune_orphan_svgs(examples_dir)

      expect(File).to exist(nested)
    end

    # A symlink inside examples/ passes a containment test on its directory
    # and still resolves somewhere else, so deleting through one would reach
    # a file the task has no claim on.
    # Asserting the TARGET survives proves nothing: deleting a symlink only
    # unlinks the link. The property is that the task does not manage a
    # symlink at all, so the link itself is still there afterwards.
    it 'refuses an orphan that is a symlink out of the tree' do
      outside = Dir.mktmpdir('sirena-outside')
      target = File.join(outside, 'victim.svg')
      File.write(target, '<svg>outside</svg>')
      FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
      link = File.join(examples_dir, 'flowchart', 'link.svg')
      File.symlink(target, link)

      described_class.prune_orphan_svgs(examples_dir)

      expect([File.symlink?(link), File.exist?(target)]).to eq([true, true])
    ensure
      FileUtils.remove_entry(outside) if outside
    end
  end

  # The only thing standing between a source that stops rendering and the gem
  # shipping its stale picture forever. Deleting the call in :generate left the
  # whole suite green before these.
  describe '.handle_failed_svgs' do
    def handle(failures)
      described_class.handle_failed_svgs(failures, examples_dir)
    end

    let(:expected_source) { EXPECTED_UNRENDERABLE_SOURCES.first }
    # Derived, not typed out: naming the source by position and its SVG by
    # hand let a reorder of the constant pair the two up wrongly.
    let(:expected_svg) { expected_source.sub(/\.mmd\z/, '.svg') }

    it 'deletes the stale SVG of a source that is expected not to render' do
      svg = write(expected_svg)

      expect { handle([[expected_source, svg]]) }.to output.to_stdout
      expect(File).not_to exist(svg)
    end

    it 'says nothing when the stale SVG is already gone' do
      missing = File.join(examples_dir, expected_svg)

      expect { handle([[expected_source, missing]]) }.not_to output.to_stdout
    end

    # An unexpected failure is a regression, not a cleanup. Exiting before any
    # delete is what keeps a real breakage from quietly erasing the evidence.
    it 'exits without deleting anything when an unexpected source failed' do
      svg = write('flowchart/01-basic.svg')

      expect { handle([['flowchart/01-basic.mmd', svg]]) }
        .to raise_error(SystemExit).and(output(/Unexpected/).to_stdout)
      expect(File).to exist(svg)
    end

    it "keeps an expected failure's SVG when an unexpected one shares the run" do
      kept = write(expected_svg)
      unexpected_svg = write('flowchart/01-basic.svg')

      expect do
        handle([[expected_source, kept], ['flowchart/01-basic.mmd', unexpected_svg]])
      end.to raise_error(SystemExit).and(output(/Unexpected/).to_stdout)
      expect(File).to exist(kept)
    end

    it 'does nothing when every source rendered' do
      svg = write('flowchart/01-basic.svg')

      expect { handle([]) }.not_to raise_error
      expect(File).to exist(svg)
    end
  end

  # Driven against a throwaway tree rather than pinned on the task's source
  # text. The two examples here used to assert that the rake file CONTAINED a
  # call; both stayed green while the task handed nothing to the cleanup.
  describe '.generate_examples' do
    let(:source) { "flowchart TD\n  A --> B\n" }

    it 'writes each SVG beside the source it came from' do
      write('flowchart/01-basic.mmd', source)

      generated, failed = silently { described_class.generate_examples(examples_dir) }

      expect([generated, failed]).to eq([1, []])
      expect(File.read(File.join(examples_dir, 'flowchart/01-basic.svg'))).to include('<svg')
    end

    # File.write truncates before it writes, so a render that produced nothing
    # used to leave a zero-byte SVG and still count as generated.
    it 'keeps the previous SVG intact when a source renders nothing' do
      write('flowchart/01-basic.mmd', source)
      svg = write('flowchart/01-basic.svg', '<svg>previous</svg>')
      allow(Sirena).to receive(:render).and_return(nil)

      generated, failed = silently { described_class.generate_examples(examples_dir) }

      expect([generated, failed.map(&:first)]).to eq([0, ['flowchart/01-basic.mmd']])
      expect(File.read(svg)).to eq('<svg>previous</svg>')
    end

    # The nil case is caught before any write, so it cannot see the rename.
    # Only a write that dies PARTWAY can, which is the case that left a
    # 1,100-byte SVG truncated to 32.
    it 'keeps the previous SVG whole when the write dies partway' do
      write('flowchart/01-basic.mmd', source)
      svg = write('flowchart/01-basic.svg', '<svg>previous</svg>')
      fail_temporary_write_partway

      silently { described_class.generate_examples(examples_dir) }

      expect(File.read(svg)).to eq('<svg>previous</svg>')
    end

    # A symlinked diagram directory resolves outside examples/, and the loop
    # would write and delete there while reporting success.
    it 'refuses a diagram directory that is a symlink out of the tree' do
      outside = Dir.mktmpdir('sirena-outside')
      File.write(File.join(outside, 'escaped.mmd'), source)
      File.symlink(outside, File.join(examples_dir, 'linked'))

      generated, failed = nil
      output = capture { generated, failed = described_class.generate_examples(examples_dir) }

      # Not merely "nothing was written outside" -- write_svg refuses that on
      # its own, so this passed with the skip deleted. Walking the directory
      # at all records a failed render, so an empty failure list is what
      # proves it was never entered.
      expect([generated, failed]).to eq([0, []])
      expect(output).to include('skipped linked')
      expect(File).not_to exist(File.join(outside, 'escaped.svg'))
    ensure
      FileUtils.remove_entry(outside) if outside
    end

    # Generation must not delete a file it cannot prove it created; Sirena
    # stamps no provenance, so a sourceless SVG is reported and left alone.
    # Driving the whole of generation, not the reporter alone: the point is
    # that a routine regeneration leaves it there, and calling the reporter
    # directly cannot see a generation that deletes.
    it 'reports a sourceless SVG without deleting it' do
      write('flowchart/01-basic.mmd', source)
      orphan = write('flowchart/hand-drawn.svg', '<svg>by hand</svg>')

      output = capture { described_class.generate_examples(examples_dir) }

      expect(output).to include('hand-drawn.svg')
      expect(File.read(orphan)).to eq('<svg>by hand</svg>')
    end
  end

  # Reached only if diagram_dirs ever stops skipping a symlinked directory.
  # Kept as a second line of defence because the failure it prevents is
  # overwriting a file outside the repository, and tested directly because an
  # unreachable guard is one nobody notices breaking.
  describe '.write_svg' do
    it 'refuses to write outside the examples tree' do
      outside = Dir.mktmpdir('sirena-outside')
      victim = File.join(outside, 'victim.svg')
      File.write(victim, '<svg>outside</svg>')

      expect { described_class.write_svg(victim, '<svg>new</svg>', examples_dir) }
        .to raise_error(/refused to write outside/)
      expect(File.read(victim)).to eq('<svg>outside</svg>')
    ensure
      FileUtils.remove_entry(outside) if outside
    end

    # The temporary name is predictable, and an ordinary write follows
    # whatever already answers to it. A leftover from a killed run, or a link
    # planted there, would otherwise be written straight through.
    it 'aborts rather than writing through a name already in the temporary slot' do
      outside = Dir.mktmpdir('sirena-outside')
      victim = File.join(outside, 'victim')
      File.write(victim, 'KEEP ME')
      FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
      target = File.join(examples_dir, 'flowchart', 'a.svg')
      File.write(target, '<svg>previous</svg>')
      # The name carries a random component, so it is pinned here rather than
      # guessed; the guard has to hold even when the name IS known.
      allow(SecureRandom).to receive(:hex).and_return('feedface')
      planted = File.join(examples_dir, 'flowchart', ".sirena-#{Process.pid}-feedface.tmp")
      File.symlink(victim, planted)

      expect { described_class.write_svg(target, '<svg>new</svg>', examples_dir) }
        .to raise_error(Errno::EEXIST)
      expect([File.read(victim), File.read(target), File.symlink?(planted)])
        .to eq(['KEEP ME', '<svg>previous</svg>', true])
    ensure
      FileUtils.remove_entry(outside) if outside
    end

    # The guard is a check on the rendered document, not on nil alone: an
    # error page or an empty string is a String too, and accepting one would
    # replace a good SVG with it.
    it 'refuses a render that is a String but not an SVG document' do
      target = File.join(examples_dir, 'flowchart', 'a.svg')
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, '<svg>previous</svg>')

      expect { described_class.write_svg(target, 'Internal Server Error', examples_dir) }
        .to raise_error(/rendered no SVG document/)
      expect(File.read(target)).to eq('<svg>previous</svg>')
    end

    it 'leaves no debris behind when the write dies partway' do
      target = File.join(examples_dir, 'flowchart', 'a.svg')
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, '<svg>previous</svg>')
      fail_temporary_write_partway

      expect { described_class.write_svg(target, '<svg>new</svg>', examples_dir) }
        .to raise_error(Errno::EFBIG)
      expect(Dir.glob(File.join(examples_dir, 'flowchart', '.*.tmp'))).to be_empty
    end

    it 'refuses a target inside the tree that is a link elsewhere' do
      outside = Dir.mktmpdir('sirena-outside')
      victim = File.join(outside, 'victim.svg')
      File.write(victim, 'KEEP ME')
      FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
      target = File.join(examples_dir, 'flowchart', 'a.svg')
      File.symlink(victim, target)

      expect { described_class.write_svg(target, '<svg>new</svg>', examples_dir) }
        .to raise_error(/refused to write outside/)
      expect(File.read(victim)).to eq('KEEP ME')
    ensure
      FileUtils.remove_entry(outside) if outside
    end

    # Once renamed, the temporary name belongs to nobody. Unlinking it anyway
    # is how one run removed the temporary file of another.
    it 'unlinks nothing once the rename has succeeded' do
      target = File.join(examples_dir, 'flowchart', 'a.svg')
      FileUtils.mkdir_p(File.dirname(target))

      allow(FileUtils).to receive(:rm_f).and_call_original

      described_class.write_svg(target, '<svg>fresh</svg>', examples_dir)

      expect(FileUtils).not_to have_received(:rm_f)
    end

    it 'writes a rendered document to a path inside the tree' do
      target = File.join(examples_dir, 'flowchart', '01-basic.svg')
      FileUtils.mkdir_p(File.dirname(target))

      described_class.write_svg(target, '<svg>fresh</svg>', examples_dir)

      expect(File.read(target)).to eq('<svg>fresh</svg>')
    end
  end

  # Both defects here were found by a reviewer building the tree by hand, and
  # neither is exotic: a directory may legitimately be named with a glob
  # character, and a link inside examples/ resolves to a real directory that
  # passes a containment test on its own.
  describe 'unusual but legitimate names' do
    let(:source) { "flowchart TD\n  A --> B\n" }

    it 'treats a directory named with glob syntax as one literal directory' do
      FileUtils.mkdir_p([File.join(examples_dir, 'gantt'), File.join(examples_dir, 'g*')])
      File.write(File.join(examples_dir, 'gantt', '01.mmd'), source)
      by_hand = File.join(examples_dir, 'g*', '01.svg')
      File.write(by_hand, 'HAND WRITTEN')

      generated, = silently { described_class.generate_examples(examples_dir) }

      # One, not two: globbing the literal name `g*` reaches gantt as well and
      # renders it a second time under the wrong directory.
      expect(generated).to eq(1)
      expect([File.read(by_hand), File.exist?(File.join(examples_dir, 'gantt', '01.svg'))])
        .to eq(['HAND WRITTEN', true])
    end

    it 'does not reach a deeper file through a link inside the tree' do
      FileUtils.mkdir_p(File.join(examples_dir, 'deep', 'nested'))
      fixture = File.join(examples_dir, 'deep', 'nested', 'fixture.svg')
      File.write(fixture, 'NESTED FIXTURE')
      File.symlink(File.join(examples_dir, 'deep', 'nested'),
                   File.join(examples_dir, 'alias'))

      described_class.prune_orphan_svgs(examples_dir)

      expect(File).to exist(fixture)
    end
  end

  # Every one of these was found by a reviewer building the tree by hand.
  # None is exotic: a folder can be a link, a folder can be unreadable, a
  # render can fail while still containing the word svg, and a name can be
  # long.
  describe 'refusing what it did not create' do
    let(:source) { "flowchart TD\n  A --> B\n" }

    it 'refuses to work under an examples root that is a link' do
      real = Dir.mktmpdir('sirena-real')
      FileUtils.mkdir_p(File.join(real, 'flowchart'))
      handmade = File.join(real, 'flowchart', 'handmade.svg')
      File.write(handmade, 'HANDMADE')
      linked_root = File.join(examples_dir, 'linked-root')
      File.symlink(real, linked_root)

      expect { described_class.prune_orphan_svgs(linked_root) }
        .to raise_error(/examples root must not be a link/)
      expect(File.read(handmade)).to eq('HANDMADE')
    ensure
      FileUtils.remove_entry(real) if real
    end

    # Swallowing the error made an unreadable directory look like an empty
    # one, so generation reported success having rewritten nothing.
    it 'fails loudly when a diagram directory cannot be read' do
      locked = File.join(examples_dir, 'locked')
      FileUtils.mkdir_p(locked)
      File.write(File.join(locked, 'a.mmd'), source)
      File.chmod(0o000, locked)

      expect { silently { described_class.generate_examples(examples_dir) } }
        .to raise_error(SystemCallError)
    ensure
      File.chmod(0o755, locked) if locked
    end

    # One table rather than one example per string: the property is where the
    # root element sits, and the shapes differ only in how that root is
    # spelled.
    it 'accepts every spelling of an SVG root and nothing else' do
      accepted = ['<svg/>', '<?xml version="1.0"?><svg/>', '<svg xmlns="x"/>',
                  "<svg\n width=\"1\">x</svg>", '<!-- note --><svg/>']
      rejected = ['<html><svg/></html>', '', 'Error 500', '<svgx/>', nil]

      expect(accepted.map { |doc| described_class.svg_document?(doc) }).to all(be(true))
      expect(rejected.map { |doc| described_class.svg_document?(doc) }).to all(be(false))
    end

    it 'refuses a render that only contains an SVG element' do
      target = File.join(examples_dir, 'flowchart', 'a.svg')
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, '<svg>previous</svg>')
      payload = '<html><body>Error 500 <svg width="1"></svg></body></html>'

      expect { described_class.write_svg(target, payload, examples_dir) }
        .to raise_error(/rendered no SVG document/)
      expect(File.read(target)).to eq('<svg>previous</svg>')
    end

    it 'ignores a source that is a link' do
      outside = Dir.mktmpdir('sirena-outside')
      File.write(File.join(outside, 'ext.mmd'), source)
      FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
      File.symlink(File.join(outside, 'ext.mmd'),
                   File.join(examples_dir, 'flowchart', 'linked.mmd'))

      generated, failed = silently { described_class.generate_examples(examples_dir) }

      expect([generated, failed]).to eq([0, []])
      expect(File).not_to exist(File.join(examples_dir, 'flowchart', 'linked.svg'))
    ensure
      FileUtils.remove_entry(outside) if outside
    end

    # One predicate for both callers: generation used File.file? and pruning
    # used File.exist?, so a .mmd link to a directory was a source to one and
    # not the other, and the SVG beside it could never be removed.
    it 'treats a .mmd link to a directory as no source at all' do
      flowchart = File.join(examples_dir, 'flowchart')
      FileUtils.mkdir_p([flowchart, File.join(examples_dir, 'adir')])
      File.symlink(File.join(examples_dir, 'adir'), File.join(flowchart, 'ghost.mmd'))
      File.write(File.join(flowchart, 'ghost.svg'), 'STALE')

      expect(described_class.orphan_svgs(examples_dir).map { |path| File.basename(path) })
        .to eq(['ghost.svg'])
    end

    it 'leaves an entry that is not a plain file where it is' do
      flowchart = File.join(examples_dir, 'flowchart')
      FileUtils.mkdir_p(flowchart)
      fifo = File.join(flowchart, 'a.svg')
      system('mkfifo', fifo)

      expect { described_class.write_svg(fifo, '<svg>x</svg>', examples_dir) }
        .to raise_error(/refused to write outside/)
      expect(File.ftype(fifo)).to eq('fifo')
    end

    # The temporary name used to embed the target's, so a legal source name
    # produced an illegal temporary one.
    it 'generates a source whose name is as long as the filesystem allows' do
      flowchart = File.join(examples_dir, 'flowchart')
      FileUtils.mkdir_p(flowchart)
      File.write(File.join(flowchart, "#{'a' * 247}.mmd"), source)

      generated, failed = silently { described_class.generate_examples(examples_dir) }

      expect([generated, failed]).to eq([1, []])
    end

    it 'replaces an existing SVG with the new bytes and counts it once' do
      flowchart = File.join(examples_dir, 'flowchart')
      FileUtils.mkdir_p(flowchart)
      File.write(File.join(flowchart, '01.mmd'), source)
      stale = File.join(flowchart, '01.svg')
      File.write(stale, '<svg>STALE</svg>')

      generated, = silently { described_class.generate_examples(examples_dir) }

      expect(generated).to eq(1)
      expect(File.read(stale)).to start_with('<svg')
      expect(File.read(stale)).not_to include('STALE')
    end

    # A later source must still be rendered after an earlier one fails.
    it 'keeps generating after a source fails' do
      flowchart = File.join(examples_dir, 'flowchart')
      FileUtils.mkdir_p(flowchart)
      File.write(File.join(flowchart, '01-bad.mmd'), 'not a diagram at all')
      File.write(File.join(flowchart, '02-good.mmd'), source)

      generated, failed = silently { described_class.generate_examples(examples_dir) }

      expect([generated, failed.map(&:first)]).to eq([1, ['flowchart/01-bad.mmd']])
      expect(File).to exist(File.join(flowchart, '02-good.svg'))
    end
  end

  describe '.theme_for' do
    it 'reads the theme its metadata names' do
      mmd = write('flowchart/01-basic.mmd')
      write('flowchart/01-basic.yml', YAML.dump('theme' => 'dark'))

      expect(described_class.theme_for(mmd)).to eq('dark')
    end

    it 'falls back to default when the source carries no metadata' do
      mmd = write('flowchart/01-basic.mmd')

      expect(described_class.theme_for(mmd)).to eq('default')
    end

    it 'falls back to default when the metadata names no theme' do
      mmd = write('flowchart/01-basic.mmd')
      write('flowchart/01-basic.yml', YAML.dump('title' => 'Basic'))

      expect(described_class.theme_for(mmd)).to eq('default')
    end
  end
end
