# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'rake'
require 'tmpdir'
require 'securerandom'
require 'stringio'
require 'yaml'
require 'English'

# The generation task no longer deletes anything -- that ability was removed
# after three rounds of guards each produced a new deletion path, and only
# the two prune helpers can delete now. Nothing else in the suite calls it: the
# conformance gate reads what is on disk, so it catches an orphan that already
# shipped and says nothing about whether the sweeper removes one. Disabling the
# sweep left the whole suite green, which is why this exists.
#
# The rake file is loaded rather than reimplemented, so the helpers under test
# are the ones the task runs. Loading it defines tasks into the default Rake
# application; none is invoked here.
TASKS_RAKE_FILE = File.expand_path('../../../lib/tasks/examples.rake', __dir__)
EXAMPLE_TASKS_FILE = File.expand_path('../../../lib/tasks/example_tasks.rb', __dir__)
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

    # BLOCKER. The list of orphans was built once and then deleted from, so a
    # source restored between those two steps lost its freshly generated SVG.
    # Codex reproduced it by pausing prune mid-loop; this reproduces it
    # deterministically by making the first look see the orphan and the second
    # see the restored source, which is exactly what the pause created.
    it 'keeps an SVG whose source is restored after the orphan list was built' do
      restored = write('flowchart/03-restored.svg')
      stale_list = [restored]

      # First call: the orphan list, as prune builds it. Every later call sees
      # the world after the source came back.
      allow(described_class).to receive(:orphan_svgs).and_return(stale_list, [])

      expect(silently { described_class.prune_orphan_svgs(examples_dir) }).to eq(0)
      expect(File).to exist(restored)
    end

    it 'still deletes an orphan that is an orphan on both looks' do
      orphan = write('flowchart/04-gone.svg')

      expect(silently { described_class.prune_orphan_svgs(examples_dir) }).to eq(1)
      expect(File).not_to exist(orphan)
    end
  end

  describe '.with_examples_lock' do
    # generate and prune both take this, so they cannot interleave at all --
    # the re-decide above covers a source restored by hand, which no lock of
    # ours can serialise.
    def try_lock
      path = described_class.examples_lock_path(examples_dir)
      File.open(path, File::RDWR | File::CREAT) { |h| h.flock(File::LOCK_EX | File::LOCK_NB) }
    end

    it 'refuses a second holder while the first holds it' do
      held = nil
      described_class.with_examples_lock(examples_dir) { held = try_lock }

      expect(held).to be(false)
    end

    it 'releases the lock when the block raises' do
      expect { described_class.with_examples_lock(examples_dir) { raise 'boom' } }
        .to raise_error('boom')

      expect(try_lock).to eq(0)
    end

    # Windows refuses to open a directory. Refuse it here too, so a lock taken
    # on the examples root itself fails on every platform, not only there.
    it 'never opens the examples directory itself' do
      allow(File).to receive(:open).and_wrap_original do |original, path, *rest, &block|
        raise Errno::EISDIR, path.to_s if File.directory?(path.to_s)

        original.call(path, *rest, &block)
      end

      expect { |probe| described_class.with_examples_lock(examples_dir, &probe) }
        .to yield_control
    end
  end

  describe '.copy_to_docs' do
    # A link inside examples/ resolves somewhere this task has no claim on,
    # whether it is a whole diagram directory or one SVG.
    it 'copies plain SVGs and skips a linked directory or file' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-outside') do |outside|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg/>')
          File.write(File.join(outside, 'secret.svg'), '<svg/>')
          File.symlink(outside, File.join(examples_dir, 'linked'))
          File.symlink(File.join(outside, 'secret.svg'),
                       File.join(examples_dir, 'flowchart', 'b.svg'))

          copied = described_class.copy_to_docs(examples_dir, docs)

          expect([copied, Dir.glob('**/*', base: docs).sort])
            .to eq([[['flowchart', 1]], ['flowchart', 'flowchart/a.svg']])
        end
      end
    end

    # `create_real_directory` uses `Dir.mkdir` for the atomic guarantee on
    # docs_assets_dir itself, which is not recursive -- a genuinely fresh
    # checkout with no docs/assets directory at all yet, not an attack, is
    # the ordinary first run. Reproduced before this case was handled: a
    # docs_assets_dir several levels below a directory that does not exist
    # yet raised a raw Errno::ENOENT instead of creating the tree.
    it 'creates docs_assets_dir and every ancestor when none of them exist yet' do
      Dir.mktmpdir('sirena-outside') do |outside|
        FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
        File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg/>')
        docs = File.join(outside, 'nested', 'docs', 'assets', 'examples')
        expect(File).not_to exist(File.dirname(docs))

        copied = described_class.copy_to_docs(examples_dir, docs)

        expect([copied, Dir.glob('**/*', base: docs).sort])
          .to eq([[['flowchart', 1]], ['flowchart', 'flowchart/a.svg']])
      end
    end

    it 'refuses a docs root that is itself a link' do
      Dir.mktmpdir('sirena-outside') do |outside|
        FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
        File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg/>')
        linked_docs = "#{outside}-link"
        File.symlink(outside, linked_docs)

        expect { described_class.copy_to_docs(examples_dir, linked_docs) }
          .to raise_error(/docs assets root must not be a link/)
      ensure
        FileUtils.rm_f(linked_docs) if linked_docs
      end
    end

    # `FileUtils.mkdir_p` treats an existing symlinked directory as "already
    # there" and does nothing, so `FileUtils.cp` right after it would follow
    # the link and write the SVG wherever it points -- outside docs_dir
    # entirely. Reproduced before this guard existed: the copy landed inside
    # `outside/`, never inside `docs/flowchart/`.
    it 'skips a diagram type whose docs target is already a link, rather than writing through it' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-outside') do |outside|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg/>')
          File.symlink(outside, File.join(docs, 'flowchart'))

          copied = described_class.copy_to_docs(examples_dir, docs)

          expect(copied).to eq([])
          expect(File.symlink?(File.join(docs, 'flowchart'))).to be(true)
          expect(File).not_to exist(File.join(outside, 'a.svg'))
        end
      end
    end

    # One level deeper than the directory-level guard above: `target_dir`
    # itself is a real directory, but the SVG's own slot inside it is a link.
    # `FileUtils.cp(svg_file, target_dir)` resolves that to
    # File.join(target_dir, basename(svg_file)) and opens it for writing,
    # which follows the link -- reproduced before this guard existed, with
    # the copy landing inside `outside/` while `docs/flowchart/a.svg` stayed
    # a symlink pointing there.
    it 'refuses to write through a docs SVG slot that is itself a link' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-outside') do |outside|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg>new</svg>')
          FileUtils.mkdir_p(File.join(docs, 'flowchart'))
          File.write(File.join(outside, 'secret.svg'), 'outside original')
          File.symlink(File.join(outside, 'secret.svg'),
                       File.join(docs, 'flowchart', 'a.svg'))

          copied = described_class.copy_to_docs(examples_dir, docs)

          expect([copied, File.symlink?(File.join(docs, 'flowchart', 'a.svg')),
                  File.read(File.join(outside, 'secret.svg'))])
            .to eq([[['flowchart', 0]], true, 'outside original'])
        end
      end
    end

    # A DIRECT symlink at the leaf is not the only way through: a leaf that is
    # a real DIRECTORY containing an inner symlink of the same basename is not
    # itself a symlink, so the guard above alone passes it -- and
    # `FileUtils.cp(svg_file, target_dir)` then treats that directory as a
    # destination CONTAINER, writing to File.join(target_dir,
    # basename(svg_file)) itself, which resolves the inner symlink and
    # follows it. Reproduced before this second condition existed: the copy
    # landed inside `outside/` while `docs/flowchart/a.svg/` stayed a
    # directory holding the untouched inner link.
    it 'refuses to write through a docs SVG slot that is a directory holding an inner link of the same name' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-outside') do |outside|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg>new</svg>')
          File.write(File.join(outside, 'secret.svg'), 'outside original')
          FileUtils.mkdir_p(File.join(docs, 'flowchart', 'a.svg'))
          File.symlink(File.join(outside, 'secret.svg'),
                       File.join(docs, 'flowchart', 'a.svg', 'a.svg'))

          copied = described_class.copy_to_docs(examples_dir, docs)

          expect([copied, File.directory?(File.join(docs, 'flowchart', 'a.svg')),
                  File.read(File.join(outside, 'secret.svg'))])
            .to eq([[['flowchart', 0]], true, 'outside original'])
        end
      end
    end

    # `docs/assets` itself is not the leaf `verified_root` receives -- the
    # literal path `docs_assets_dir` names (e.g. `docs/assets/examples`) is
    # not itself a link, only reached through a symlinked ANCESTOR. A
    # leaf-only check let this straight through; reproduced before the
    # ancestor walk existed: `docs/assets` symlinked outside the repo
    # received every copy. The walk is bounded to GEM_ROOT (see its comment
    # in lib/tasks/examples.rake), so this stubs GEM_ROOT to the test's own
    # tmpdir -- the same boundary a real call site gets from its own
    # checkout root, without reaching into the real gem checkout.
    it 'refuses a docs root reached through a symlinked ancestor, not just a link itself' do
      Dir.mktmpdir('sirena-root') do |root|
        stub_const('ExampleTasks::GEM_ROOT', root)

        Dir.mktmpdir('sirena-outside') do |outside|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg/>')
          File.symlink(outside, File.join(root, 'assets'))
          docs_assets_dir = File.join(root, 'assets', 'examples')

          expect { described_class.copy_to_docs(examples_dir, docs_assets_dir) }
            .to raise_error(/docs assets root sits beneath a symlinked directory/)
        end
      end
    end

    # The ancestor check above runs ONCE, before `Dir.mkdir` -- nothing
    # carries it forward, so `Dir.mkdir` resolving docs_assets_dir by name
    # would follow a symlink raced into an ancestor after the check. Stubs
    # `Dir.mkdir` to swap the ancestor for a symlink right before the call.
    # `Dir.mkdir` itself succeeds here (the hijacked leaf is genuinely
    # fresh); the property that matters is that the re-verification raises
    # before anything is copied into that leaf.
    it 'refuses rather than writing through an ancestor symlink raced in between the ancestor check and directory creation' do
      Dir.mktmpdir('sirena-root') do |root|
        stub_const('ExampleTasks::GEM_ROOT', root)

        Dir.mktmpdir('sirena-attacker') do |attacker|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg/>')
          docs_assets_dir = File.join(root, 'docs', 'assets', 'examples')
          hijacked_ancestor = File.join(root, 'docs', 'assets')

          allow(Dir).to receive(:mkdir).and_wrap_original do |original, path, *rest|
            if File.expand_path(path) == docs_assets_dir
              FileUtils.rm_rf(hijacked_ancestor)
              File.symlink(attacker, hijacked_ancestor)
            end
            original.call(path, *rest)
          end

          expect { described_class.copy_to_docs(examples_dir, docs_assets_dir) }
            .to raise_error(/docs assets root sits beneath a symlinked directory/)
          expect(Dir.children(File.join(attacker, 'examples'))).to eq([])
        end
      end
    end

    # The two specs above only ever exercise `verified_root`'s GEM_ROOT
    # branch on the RAISING arm -- an attack whose hijacked path can never
    # equal `expected` regardless of how `expected` itself is computed, so a
    # broken `expected` (e.g. built from the wrong operand, or dropping the
    # suffix entirely) still raises and still passes both specs. Nothing
    # anywhere else in this file stubs GEM_ROOT at all, so nothing exercises
    # this branch's non-raising arm: whether `expected` is actually computed
    # correctly for an ordinary, un-attacked nested path -- the shape every
    # real invocation of this task takes, since a real GEM_ROOT is the gem's
    # own checkout and a real docs_assets_dir sits beneath it. This is the
    # only spec in the file where that arm is live: no symlink anywhere,
    # GEM_ROOT stubbed so the branch is entered, and the assertion is that
    # the ordinary copy succeeds rather than raising a false positive.
    it 'succeeds on an ordinary nested docs root once GEM_ROOT makes the ancestor check live' do
      Dir.mktmpdir('sirena-root') do |root|
        stub_const('ExampleTasks::GEM_ROOT', root)

        examples = File.join(root, 'examples')
        FileUtils.mkdir_p(File.join(examples, 'flowchart'))
        File.write(File.join(examples, 'flowchart', 'a.svg'), '<svg/>')
        docs_assets_dir = File.join(root, 'docs', 'assets', 'examples')

        copied = described_class.copy_to_docs(examples, docs_assets_dir)

        expect([copied, Dir.glob('**/*', base: docs_assets_dir).sort])
          .to eq([[['flowchart', 1]], ['flowchart', 'flowchart/a.svg']])
      end
    end

    # Races a symlink into place right after the per-file guard clears it,
    # immediately before `File.rename` -- which replaces the directory
    # entry atomically rather than following it. NOTE: mock against
    # `FileUtils.cp` instead would never fire (a directory `dest` receives
    # the DIRECTORY, not the joined path). `File.expand_path` on `to` is
    # required: `Dir.chdir` pins the process to `docs/flowchart`, resolved
    # via `File.realpath(docs)` to match macOS's `/var -> /private/var`.
    it 'does not write through a destination symlink raced in after the per-file guard clears it' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-outside') do |outside|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg>real content</svg>')
          victim = File.join(outside, 'victim.svg')
          File.write(victim, 'KEEP ME')
          destination = File.join(File.realpath(docs), 'flowchart', 'a.svg')

          allow(File).to receive(:rename).and_wrap_original do |original, from, to|
            File.symlink(victim, to) if File.expand_path(to) == destination
            original.call(from, to)
          end

          copied = described_class.copy_to_docs(examples_dir, docs)

          expect([copied, File.symlink?(destination), File.read(victim)])
            .to eq([[['flowchart', 1]], false, 'KEEP ME'])
        end
      end
    end

    # SOURCE has its own, separate race: `svg_files` is validated once when
    # `copy_to_docs` builds its work list, long before the source is read --
    # the destination-side rename guard above does nothing here, since the
    # vulnerable operation is the read, not the rename. Wraps `File.open` so
    # the source becomes a symlink only in the gap right before it opens.
    it 'does not read through a source symlink raced in immediately before the read' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-outside') do |outside|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          source = File.join(examples_dir, 'flowchart', 'a.svg')
          File.write(source, '<svg>real content</svg>')
          secret = File.join(outside, 'secret.txt')
          File.write(secret, 'TOP SECRET')

          allow(File).to receive(:open).and_wrap_original do |original, path, *rest, &block|
            if path == source && File.file?(path) && !File.symlink?(path)
              File.delete(source)
              File.symlink(secret, source)
            end
            original.call(path, *rest, &block)
          end

          expect { described_class.copy_to_docs(examples_dir, docs) }
            .to raise_error(/source became unsafe to read/)
          expect(File).not_to exist(File.join(docs, 'flowchart', 'a.svg'))
          expect(File.read(secret)).to eq('TOP SECRET')
        end
      end
    end

    # `Dir.mkdir` fails outright on anything already at that name (unlike
    # the `mkdir_p` this replaced), so racing a symlink into target_dir's
    # name should make copy_to_docs raise, not silently redirect writes.
    #
    # The stub matches by resolving whatever `Dir.mkdir` actually receives
    # against the process's CURRENT directory (relative to the pin on
    # docs_assets_dir, not the absolute target_dir path), against
    # `File.realpath(docs)` rather than the raw mktmpdir path -- `Dir.chdir`
    # resolves through macOS's `/var -> /private/var`, so matching against
    # the un-resolved alias would never fire.
    it 'refuses rather than writing into a target_dir symlink raced in right before creation' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-attacker') do |attacker|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg>real content</svg>')
          target_dir = File.join(File.realpath(docs), 'flowchart')

          allow(Dir).to receive(:mkdir).and_wrap_original do |original, path, *rest|
            if File.expand_path(path) == target_dir && !File.exist?(path)
              File.symlink(attacker, path)
            end
            original.call(path, *rest)
          end

          expect { described_class.copy_to_docs(examples_dir, docs) }
            .to raise_error(/docs target for flowchart became a symlink/)
          expect([File.symlink?(target_dir), Dir.children(attacker)]).to eq([true, []])
        end
      end
    end

    # The gap `within_pinned_directory` cannot close by construction --
    # entering a directory by name still has to resolve that name once --
    # is detected instead: identity is captured right before the chdir and
    # re-checked right after, so a symlink that wins this one-syscall race
    # is caught rather than silently walked into.
    it 'refuses rather than proceeding when docs_assets_dir changes identity right before the pin is taken' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-attacker') do |attacker|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg>real content</svg>')

          allow(Dir).to receive(:chdir).and_wrap_original do |original, path, &block|
            if File.expand_path(path) == docs
              FileUtils.rm_rf(docs)
              File.symlink(attacker, docs)
            end
            original.call(path, &block)
          end

          expect { described_class.copy_to_docs(examples_dir, docs) }
            .to raise_error(/docs assets root changed identity between verification and use/)
          expect(Dir.children(attacker)).to eq([])
        end
      end
    end

    # The same detection, one level down: target_dir's own identity can
    # change in the gap between `create_real_directory` confirming it and
    # `within_pinned_directory` entering it for the per-file loop. Matched
    # against `File.realpath` of docs for the same reason as the sibling
    # test above.
    it 'refuses rather than proceeding when target_dir changes identity right before its own pin is taken' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-attacker') do |attacker|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg>real content</svg>')
          target_dir = File.join(File.realpath(docs), 'flowchart')

          allow(Dir).to receive(:chdir).and_wrap_original do |original, path, &block|
            if File.expand_path(path) == target_dir
              FileUtils.rm_rf(target_dir)
              File.symlink(attacker, target_dir)
            end
            original.call(path, &block)
          end

          expect { described_class.copy_to_docs(examples_dir, docs) }
            .to raise_error(/docs target for flowchart changed identity between verification and use/)
          expect(Dir.children(attacker)).to eq([])
        end
      end
    end

    # Proves the actual gap Codex round 3 found (HANDOFF 7): the check done
    # ONCE at loop start does not protect the rest of a multi-file loop.
    # Deliberately timed for the SECOND file, after the first has already
    # copied normally -- the harder-to-dismiss case, since it proves a
    # confirmation done before the loop started does not cover what comes
    # after it.
    it 'keeps every later file pinned to the original target_dir, even after target_dir is renamed away and replaced mid-loop' do
      Dir.mktmpdir('sirena-docs') do |docs|
        Dir.mktmpdir('sirena-attacker') do |attacker|
          FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
          File.write(File.join(examples_dir, 'flowchart', 'a.svg'), '<svg>a</svg>')
          File.write(File.join(examples_dir, 'flowchart', 'b.svg'), '<svg>b</svg>')
          target_dir = File.join(docs, 'flowchart')
          moved_aside = File.join(docs, 'flowchart-moved-by-attacker')

          renames = 0
          allow(File).to receive(:rename).and_wrap_original do |original, from, to|
            result = original.call(from, to)
            renames += 1
            if renames == 1
              # Mid-loop: swap the outer name AFTER the first file's write
              # has already landed, exactly the loop-start-only-check gap.
              FileUtils.mv(target_dir, moved_aside)
              File.symlink(attacker, target_dir)
            end
            result
          end

          copied = described_class.copy_to_docs(examples_dir, docs)

          expect(copied).to eq([['flowchart', 2]])
          expect(Dir.children(attacker)).to eq([])
          expect(Dir.children(moved_aside).sort).to eq(%w[a.svg b.svg])
        end
      end
    end
  end

  # generate never deletes a stale SVG itself — it only reports one, so a run
  # racing a concurrent writer can never destroy fresh output. Deleting is
  # `.prune_known_unrenderable_svgs`'s job, exercised in its own describe
  # block below.
  describe '.handle_failed_svgs' do
    def handle(failures)
      described_class.handle_failed_svgs(failures, examples_dir)
    end

    let(:expected_source) { EXPECTED_UNRENDERABLE_SOURCES.first }
    # Derived, not typed out: naming the source by position and its SVG by
    # hand let a reorder of the constant pair the two up wrongly.
    let(:expected_svg) { expected_source.sub(/\.mmd\z/, '.svg') }

    it 'reports, but does not delete, the stale SVG of a source that is expected not to render' do
      svg = write(expected_svg)

      expect { handle([[expected_source, svg]]) }.to output(/no longer render.*prune/m).to_stdout
      expect(File).to exist(svg)
    end

    it 'says nothing when the stale SVG is already gone' do
      missing = File.join(examples_dir, expected_svg)

      expect { handle([[expected_source, missing]]) }.not_to output.to_stdout
    end

    # A run that recorded this failure can race a concurrent run finishing and
    # writing a good SVG to the same path. Nothing here can distinguish the
    # two, which is exactly why deletion does not happen in this path at all:
    # the concurrent writer's fresh output survives by construction, not by a
    # timing check.
    it "never touches another run's SVG, even one written after this run started" do
      svg = write(expected_svg, '<svg>written by another run</svg>')

      handle([[expected_source, svg]])

      expect(File.read(svg)).to eq('<svg>written by another run</svg>')
    end

    # An unexpected failure is a regression, not a cleanup. Raising before any
    # report is what keeps a real breakage from being read as routine.
    # A plain StandardError, not SystemExit: this is a library method a
    # caller can require and call directly, and it must not end that
    # caller's whole process.
    it 'raises without deleting anything when an unexpected source failed' do
      svg = write('flowchart/01-basic.svg')

      expect { handle([['flowchart/01-basic.mmd', svg]]) }
        .to raise_error(described_class::UnexpectedRenderFailure).and(output(/Unexpected/).to_stdout)
      expect(File).to exist(svg)
    end

    it "keeps an expected failure's SVG when an unexpected one shares the run" do
      kept = write(expected_svg)
      unexpected_svg = write('flowchart/01-basic.svg')

      expect do
        handle([[expected_source, kept], ['flowchart/01-basic.mmd', unexpected_svg]])
      end.to raise_error(described_class::UnexpectedRenderFailure).and(output(/Unexpected/).to_stdout)
      expect(File).to exist(kept)
    end

    it 'does nothing when every source rendered' do
      svg = write('flowchart/01-basic.svg')

      expect { handle([]) }.not_to raise_error
      expect(File).to exist(svg)
    end
  end

  # The deliberate, standalone counterpart to .handle_failed_svgs' report: a
  # human runs this with no concurrent :generate to race, so it is the only
  # place a stale known-unrenderable SVG is actually removed.
  describe '.known_unrenderable_svgs and .prune_known_unrenderable_svgs' do
    let(:expected_source) { EXPECTED_UNRENDERABLE_SOURCES.first }
    let(:expected_svg) { expected_source.sub(/\.mmd\z/, '.svg') }

    it 'finds the stale SVG beside a source that never renders' do
      svg = write(expected_svg)
      write(expected_source)

      expect(described_class.known_unrenderable_svgs(examples_dir)).to eq([svg])
    end

    it 'ignores a source that renders normally' do
      write('flowchart/01-basic.svg')
      write('flowchart/01-basic.mmd')

      expect(described_class.known_unrenderable_svgs(examples_dir)).to eq([])
    end

    it 'deletes the stale SVG and reports how many it removed' do
      svg = write(expected_svg)

      expect(described_class.prune_known_unrenderable_svgs(examples_dir)).to eq(1)
      expect(File).not_to exist(svg)
    end

    it 'does nothing when there is no stale SVG to prune' do
      expect(described_class.prune_known_unrenderable_svgs(examples_dir)).to eq(0)
    end

    # Same containment discipline as every other write path here: a symlink
    # sitting at the expected SVG path resolves somewhere this task has no
    # claim on, so it must not be followed.
    it 'refuses a stale SVG slot that is a symlink out of the tree' do
      outside = Dir.mktmpdir('sirena-outside')
      target = File.join(outside, 'victim.svg')
      File.write(target, '<svg>outside</svg>')
      FileUtils.mkdir_p(File.dirname(File.join(examples_dir, expected_svg)))
      File.symlink(target, File.join(examples_dir, expected_svg))

      expect(described_class.prune_known_unrenderable_svgs(examples_dir)).to eq(0)
      expect(File.exist?(target)).to be(true)
    ensure
      FileUtils.remove_entry(outside) if outside
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
    #
    # A write failure is not a render failure and must not be swallowed into
    # failed_renders: doing that once let handle_failed_svgs mistake a full
    # disk for the source failing to render, and delete the SVG below on the
    # strength of it. So this now propagates out of generate_examples rather
    # than being caught, the same way an unreadable diagram directory does.
    it 'keeps the previous SVG whole and fails the task when the write dies partway' do
      write('flowchart/01-basic.mmd', source)
      svg = write('flowchart/01-basic.svg', '<svg>previous</svg>')
      fail_temporary_write_partway

      expect { silently { described_class.generate_examples(examples_dir) } }
        .to raise_error(Errno::EFBIG)
      expect(File.read(svg)).to eq('<svg>previous</svg>')
    end

    # The scenario that actually loses data: a write failure lands on a
    # source that handle_failed_svgs would treat as an EXPECTED failure, so
    # the old code never got as far as reporting an "unexpected" failure and
    # exiting — it quietly deleted the still-good SVG and reported success.
    # Proven at generate_examples alone: the fix is that it never reaches
    # handle_failed_svgs as a failed render in the first place.
    it 'never treats a write failure on an allowlisted source as an expected render failure' do
      source_path = EXPECTED_UNRENDERABLE_SOURCES.first
      svg_path = source_path.sub(/\.mmd\z/, '.svg')
      write(source_path, source)
      svg = write(svg_path, '<svg>previous good output</svg>')
      fail_temporary_write_partway

      expect { silently { described_class.generate_examples(examples_dir) } }
        .to raise_error(Errno::EFBIG)
      expect(File.read(svg)).to eq('<svg>previous good output</svg>')
    end

    # Malformed metadata is an operational failure, not evidence the source
    # itself fails to render. Reading it inside the render-failure rescue
    # gave a bad .yml on an allowlisted source the same deletion permission
    # as a genuine render failure, and deleted the still-good SVG below.
    it 'propagates a metadata error instead of treating it as a render failure' do
      source_path = EXPECTED_UNRENDERABLE_SOURCES.first
      svg_path = source_path.sub(/\.mmd\z/, '.svg')
      write(source_path, source)
      svg = write(svg_path, '<svg>previous good output</svg>')
      write(source_path.sub(/\.mmd\z/, '.yml'), "theme: [\n")

      expect { silently { described_class.generate_examples(examples_dir) } }
        .to raise_error(Psych::SyntaxError)
      expect(File.read(svg)).to eq('<svg>previous good output</svg>')
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
        .to raise_error(/refused an unsafe SVG target/)
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
        .to raise_error(/refused an unsafe SVG target/)
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
      # `*` is illegal in an NTFS filename, so this used `g*` and a real
      # directory `gantt` it collides with under Dir.glob. `{gantt}` is a
      # brace-expansion pattern with the same property — Dir.glob("{gantt}")
      # resolves to ["gantt"] on every platform — and every character in it
      # is legal on Windows, so the case still exists there to fail.
      FileUtils.mkdir_p([File.join(examples_dir, 'gantt'), File.join(examples_dir, '{gantt}')])
      File.write(File.join(examples_dir, 'gantt', '01.mmd'), source)
      by_hand = File.join(examples_dir, '{gantt}', '01.svg')
      File.write(by_hand, 'HAND WRITTEN')

      generated, = silently { described_class.generate_examples(examples_dir) }

      # One, not two: globbing the literal name `{gantt}` reaches gantt as
      # well and renders it a second time under the wrong directory.
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
    # one, so generation reported success having rewritten nothing. chmod
    # 0o000 proves this on a POSIX filesystem, but Windows ACLs do not refuse
    # the owning process a directory listing the same way, so the property —
    # that `children`'s SystemCallError propagates out of generate_examples
    # rather than being rescued — is proven by stubbing the one call that
    # would raise it, rather than by trying to make the OS refuse the read.
    it 'fails loudly when a diagram directory cannot be read' do
      locked = File.join(examples_dir, 'locked')
      FileUtils.mkdir_p(locked)
      File.write(File.join(locked, 'a.mmd'), source)
      allow(Dir).to receive(:children).and_wrap_original do |original, dir|
        raise Errno::EACCES, dir if dir == locked

        original.call(dir)
      end

      expect { silently { described_class.generate_examples(examples_dir) } }
        .to raise_error(SystemCallError)
    end

    # One table rather than one example per string: the property is where the
    # root element sits, and the shapes differ only in how that root is
    # spelled.
    it 'accepts every spelling of an SVG root and nothing else' do
      accepted = ['<svg/>', '<?xml version="1.0"?><svg/>', '<svg xmlns="x"/>',
                  "<svg\n width=\"1\">x</svg>", '<!-- note --><svg/>']
      # The malformed prefixes matter: matching one character after the name
      # accepted every one of them.
      rejected = ['<html><svg/></html>', '', 'Error 500', '<svgx/>', nil,
                  '<svg/garbage', '<svg ', '<svg/', '<svg width="1"', '<svg']

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
      # A FIFO makes the point (mkfifo has no NTFS equivalent), but the guard
      # is `File.lstat(path).file?`, which is exactly as false for a plain
      # directory sitting at the target path — same branch, no platform tool
      # required.
      flowchart = File.join(examples_dir, 'flowchart')
      FileUtils.mkdir_p(flowchart)
      not_a_file = File.join(flowchart, 'a.svg')
      FileUtils.mkdir_p(not_a_file)

      expect { described_class.write_svg(not_a_file, '<svg>x</svg>', examples_dir) }
        .to raise_error(/refused an unsafe SVG target/)
      expect(File.ftype(not_a_file)).to eq('directory')
    end

    # The temporary name used to embed the target's, so a legal source name
    # produced an illegal temporary one.
    it 'generates a source with a 251-byte name' do
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

    # This file's own doc comment claims ExampleTasks is a plain library a
    # caller may require and call directly -- but every caller in this repo
    # happens to `require 'yaml'` first (the rake tasks in their bodies, this
    # spec file at its own top), so a module that forgot to require it itself
    # would pass every other example here anyway: `yaml` is already loaded
    # into the process by the time any of them run. Only a fresh process that
    # loads the rake file WITHOUT requiring yaml first can catch a missing
    # `require 'yaml'` inside the module.
    it 'resolves YAML without depending on a caller having required it first' do
      script = <<~RUBY
        require 'rake'
        Rake.application = Rake::Application.new
        load #{TASKS_RAKE_FILE.inspect}
        Dir.mktmpdir do |dir|
          mmd = File.join(dir, 'a.mmd')
          File.write(mmd, 'flowchart TD')
          File.write(File.join(dir, 'a.yml'), 'theme: dark')
          print ExampleTasks.theme_for(mmd)
        end
      RUBY

      output = IO.popen([RbConfig.ruby, '-rtmpdir', '-e', script], err: [:child, :out], &:read)

      expect($CHILD_STATUS).to be_success
      expect(output).to eq('dark')
    end
  end

  describe '.validate_examples' do
    # `exit` in a plain method takes the caller's whole process down, so a host
    # that requires this file loses everything on one bad example. Only the rake
    # task may decide an exit status.
    it 'raises instead of exiting when an example fails to render' do
      write('flowchart/01-broken.mmd', "flowchart TD\n  A --> \n")

      expect { described_class.validate_examples(examples_dir) }
        .to raise_error(ExampleTasks::ValidationFailed, /validation failed/)
    end

    # Malformed metadata is an operational failure, not evidence the source
    # fails to render. Reading it inside the render-failure rescue let a bad
    # .yml on an ordinary source pass as an ordinary render failure — the
    # right classification here, but the wrong reason, and the next example
    # proves why that distinction matters.
    it 'propagates a metadata error instead of treating it as a render failure' do
      write('flowchart/01-basic.mmd', "flowchart TD\n  A --> B\n")
      write('flowchart/01-basic.yml', "theme: [\n")

      expect { described_class.validate_examples(examples_dir) }
        .to raise_error(Psych::SyntaxError)
    end

    # The defect this closes: on an EXPECTED_UNRENDERABLE_SOURCES entry, a
    # malformed .yml used to be caught by the same rescue that classifies a
    # genuine "known unrenderable" render failure, so validation counted it as
    # K and reported success — silently hiding a broken sidecar file behind a
    # documented one.
    it 'does not report success when an expected-unrenderable source has malformed metadata' do
      source_path = EXPECTED_UNRENDERABLE_SOURCES.first
      write(source_path, "gantt\n  title Broken\n")
      write(source_path.sub(/\.mmd\z/, '.yml'), "theme: [\n")

      expect { described_class.validate_examples(examples_dir) }
        .to raise_error(Psych::SyntaxError)
    end

    # One level deeper than the example above, and the level Codex found: the
    # .yml is VALID, and the theme it NAMES is the broken file. `theme_for`
    # only reads the sidecar, so the theme itself was loaded inside
    # `Sirena.render` -- back within the rescue that classifies render
    # failures. An allowlisted source whose theme would not load was counted
    # K and validation reported success, which is the same defect wearing a
    # second layer.
    it 'does not report success when an expected-unrenderable source names a theme that will not load' do
      source_path = EXPECTED_UNRENDERABLE_SOURCES.first
      broken_theme = File.join(examples_dir, 'broken-theme.yml')
      File.write(broken_theme, "colors: [\n")

      write(source_path, "gantt\n  title Broken\n")
      write(source_path.sub(/\.mmd\z/, '.yml'), "theme: #{broken_theme}\n")

      expect { described_class.validate_examples(examples_dir) }
        .to raise_error(Lutaml::Model::InvalidFormatError)
    end

    # The classification arithmetic itself, not just the reads that happen
    # before it: a genuine render failure on an allowlisted source must reach
    # `known_unrenderable` and must NOT fail the task. Asserted on the printed
    # count rather than a bare `not_to raise_error`, so a mutant that folds
    # `known_unrenderable` into `failure_count` cannot pass silently.
    it 'counts a real render failure on an expected-unrenderable source as known, not failed' do
      source_path = EXPECTED_UNRENDERABLE_SOURCES.first
      write(source_path, "flowchart TD\n  A --> \n")

      output = capture { described_class.validate_examples(examples_dir) }

      expect(output).to include('Known unrenderable: 1')
      expect(output).to include('Failed: 0')
    end

    # The mirror image: an allowlisted source that starts rendering again must
    # fail validation loudly, or an EXPECTED_UNRENDERABLE_SOURCES entry rots
    # into a permanent excuse nobody revisits once Sirena actually fixes it.
    it 'raises when an expected-unrenderable source unexpectedly renders' do
      source_path = EXPECTED_UNRENDERABLE_SOURCES.first
      write(source_path, "gantt\n  title Broken\n")
      allow(Sirena::Engine).to receive(:new)
        .and_return(instance_double(Sirena::Engine, render: '<svg/>'))

      expect { described_class.validate_examples(examples_dir) }
        .to raise_error(ExampleTasks::ValidationFailed, /unexpectedly renderable/)
    end

    # :generate walks sources through diagram_dirs + plain_mmd?, which skip a
    # symlink; this used a raw Dir.glob instead, which follows one -- a
    # symlinked .mmd resolved outside examples/ was read and rendered exactly
    # like a real source. Asserted on Total rather than a raise, because the
    # defect is the file being counted and read at all, not any error it
    # happens to produce.
    it 'does not read a source file that is a symlink out of the tree' do
      FileUtils.mkdir_p(File.join(examples_dir, 'flowchart'))
      outside = Dir.mktmpdir('sirena-outside')
      File.write(File.join(outside, 'escaped.mmd'), "flowchart TD\n  A --> B\n")
      File.symlink(File.join(outside, 'escaped.mmd'),
                   File.join(examples_dir, 'flowchart', 'a.mmd'))

      output = capture { described_class.validate_examples(examples_dir) }

      expect(output).to include('Total:  0')
    ensure
      FileUtils.remove_entry(outside) if outside
    end

    # The directory case, the same way generation is guarded: a symlinked
    # diagram directory resolves outside examples/ entirely, and a raw
    # Dir.glob('*/*.mmd') follows it just as readily as it would a symlinked
    # leaf file.
    it 'does not read sources inside a diagram directory that is a symlink out of the tree' do
      outside = Dir.mktmpdir('sirena-outside')
      File.write(File.join(outside, 'escaped.mmd'), "flowchart TD\n  A --> B\n")
      File.symlink(outside, File.join(examples_dir, 'linked'))

      output = capture { described_class.validate_examples(examples_dir) }

      expect(output).to include('Total:  0')
    ensure
      FileUtils.remove_entry(outside) if outside
    end

    # diagram_dirs checked File.directory? before File.symlink?, so a symlink
    # whose target does not exist failed the directory check first and was
    # skipped with no warning at all -- unlike a symlink to a real directory
    # outside examples/, which prints one. A human staring at a diagram type
    # that vanished deserves the same clue either way.
    it 'warns about a symlinked diagram directory even when its target is missing' do
      File.symlink(File.join(examples_dir, 'nonexistent-target'),
                   File.join(examples_dir, 'dangling'))

      output = capture { described_class.validate_examples(examples_dir) }

      expect(output).to include('skipped dangling, a symlinked directory that leaves examples/')
    end
  end

  # The capability, not a watcher on its use. `generate` and `validate` used to
  # be able to delete, and three rounds of guards each produced a new deletion
  # path; the fix was to take the ability away, leaving deletion only in the two
  # helpers whose names say they delete.
  #
  # Codex's Low was that nothing tests the TASK wiring: an in-memory mutation
  # inserting a prune call into the generation task left all 49 examples green.
  # Invoking rake tasks from this file would fight its design -- it loads the
  # rake file to test the HELPERS and invokes no task. This asserts the boundary
  # those helpers sit behind instead, which is the property that actually
  # matters and cannot drift silently.
  describe 'the deletion boundary' do
    # A `let`, not a constant: `Lint/ConstantDefinitionInBlock` fires on a
    # constant here, and its autocorrect turns one into a block-local, which
    # has silently made a spec assert nothing before.
    #
    # Only methods on ExampleTasks itself. The `clean` task in the namespace
    # below is deliberately destructive and is out of scope.
    let(:permitted_deleters) do
      %w[prune_orphan_svgs prune_known_unrenderable_svgs write_svg copy_through_rename atomic_write]
    end

    # Derived from the classes themselves, not hand-typed: a three-pattern
    # regex (File.delete/File.unlink/FileUtils.rm) missed FileUtils.remove_entry
    # entirely -- an in-memory mutation reintroducing deletion through it
    # produced no offenders, because nothing about that call matched any of
    # the three patterns. This walks every File/Dir/FileUtils singleton
    # method whose name reads as a delete and builds the pattern from that
    # list, so a future deletion call needs a new NAME, not a new pattern, to
    # slip past.
    let(:deletion_call_pattern) do
      qualified_names = { File => File.singleton_methods, Dir => Dir.singleton_methods,
                          FileUtils => FileUtils.singleton_methods }
        .flat_map { |klass, methods| methods.grep(/delete|unlink|remove|\Arm/).map { |m| "#{klass}.#{m}" } }

      Regexp.union(qualified_names.map { |name| /#{Regexp.escape(name)}\b/ })
    end

    def module_body(source)
      first = source.index { |line| line.start_with?('module ExampleTasks') }
      last = (first...source.size).find { |i| source[i].rstrip == 'end' }
      (first..last)
    end

    it 'confines every deletion call to the methods allowed to delete' do
      source = File.readlines(EXAMPLE_TASKS_FILE)
      current = nil
      offenders = []

      module_body(source).each do |i|
        current = Regexp.last_match(1) if source[i] =~ /^\s*def\s+([a-z_?!]+)/
        next unless source[i].match?(deletion_call_pattern)

        offenders << "#{current}:#{i + 1}" unless permitted_deleters.include?(current)
      end

      expect(offenders).to be_empty
    end
  end
end
