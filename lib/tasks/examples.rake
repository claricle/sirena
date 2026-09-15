# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'digest'
require 'securerandom'
require 'tmpdir'
require 'yaml'

# Rendering must not depend on the day it ran. Gantt derives its whole date
# range from the reference date, so an unpinned run produces different output
# every day from identical source, which makes any diff meaningless.
#
# The SVGs sit next to their .mmd sources and are tracked, because the gemspec
# ships whatever `git ls-files` returns and they go out to every user. So this
# task DOES dirty git, on purpose: regenerating is how a shipped example stays
# honest about what Sirena renders today.
EXAMPLE_TODAY = Date.new(2026, 1, 1)

# The only example sources legitimately unrenderable today.
EXPECTED_UNRENDERABLE_SOURCES = [
  'gantt/01-simple-timeline.beta.mmd',
  'packet/01-basic-packet.beta.mmd'
].freeze

# Keeps helper methods off Object; ExampleTasks itself remains top-level.
module ExampleTasks
  module_function

  # The gem's own checkout root. Every real examples_dir/docs_assets_dir this
  # task is ever given lives under it -- both are built via
  # File.expand_path('../../X', __dir__) in the rake tasks below -- so nothing
  # above this line is this task's business to judge for a symlinked ancestor.
  # `verified_root` walks ancestors only within this boundary, not all the way
  # to filesystem `/`: an unbounded walk falsely flags an ordinary OS symlink
  # no caller here can avoid (macOS routes `Dir.mktmpdir` -- what every spec's
  # examples_dir/docs_assets_dir actually is -- through `/var -> private/var`)
  # as a violation. Confirmed by execution: `File.symlink?('/var')` and
  # `File.symlink?('/tmp')` are both true on this machine.
  GEM_ROOT = File.expand_path('../..', __dir__)

  # The one place an example's theme is decided. Both :generate and :validate
  # read it here so they cannot drift into rendering the same source two ways.
  def theme_for(mmd_file)
    yml_file = mmd_file.sub(/\.mmd\z/, '.yml')
    metadata = File.exist?(yml_file) ? YAML.load_file(yml_file) : {}
    metadata['theme'] || 'default'
  end

  def validate_examples(examples_dir)
    failed = []
    known_unrenderable = []
    unexpectedly_renderable = []
    passed = 0
    total = 0

    puts "Validating examples..."
    puts ". rendered   K known unrenderable   F failure"
    puts ""

    # Enumerated the same way :generate walks sources -- diagram_dirs skips a
    # symlinked diagram directory and mmd_files_in skips a symlinked .mmd --
    # not a raw Dir.glob, which followed both and read whatever they pointed at.
    mmd_files = diagram_dirs(examples_dir).flat_map { |dir| mmd_files_in(dir) }.sort

    mmd_files.each do |mmd_file|
      total += 1
      source = File.read(mmd_file)
      relative_path = mmd_file.sub(examples_dir + '/', '')
      expected_unrenderable = EXPECTED_UNRENDERABLE_SOURCES.include?(relative_path)
      # Read outside the render-failure rescue below, the same as generation:
      # a malformed .yml is a metadata problem, not evidence the source fails
      # to render, and folding it into the rescue gave a bad .yml on an
      # allowlisted source the same "known unrenderable" pass as a genuine
      # render failure — so validation reported success on broken metadata.
      theme = theme_for(mmd_file)

      # And BUILD THE ENGINE here too, for the same reason one level down.
      # `theme_for` only reads the .yml; the theme it NAMES is loaded inside
      # `Sirena.render`, which put a broken theme FILE back inside the rescue
      # — so an allowlisted source whose theme would not load was still
      # counted "known unrenderable" and validation still reported success.
      #
      # `Engine.new` does the theme loading in its constructor, so a theme
      # that cannot load raises HERE and fails the task loudly. Verified
      # equivalent to the previous call for every built-in theme:
      # `Sirena.render(src, theme: t, today: d)` and
      # `Engine.new(theme: t, today: d).render(src)` are byte-identical.
      engine = Sirena::Engine.new(theme: theme, today: EXAMPLE_TODAY)

      begin
        engine.render(source)
        if expected_unrenderable
          unexpectedly_renderable << relative_path
          print 'F'
        else
          passed += 1
          print '.'
        end
      rescue => e
        if expected_unrenderable
          known_unrenderable << { file: relative_path, error: e.message }
          print 'K'
        else
          failed << { file: relative_path, error: e.message }
          print 'F'
        end
      end
    end

    failure_count = failed.size + unexpectedly_renderable.size

    puts "\n\n"
    puts "=" * 60
    puts "Validation Results"
    puts "=" * 60
    renderable = total - known_unrenderable.size
    puts "Total:  #{total}"
    puts "Passed: #{passed} of #{renderable} renderable " \
         "(#{renderable.zero? ? 'n/a' : "#{(passed.to_f / renderable * 100).round(1)}%"})"
    puts "Known unrenderable: #{known_unrenderable.size}"
    puts "Failed: #{failure_count}"
    puts "=" * 60

    if known_unrenderable.any?
      puts "\nKnown unrenderable:"
      known_unrenderable.each do |f|
        puts "  ⚠️  #{f[:file]}"
        puts "    #{f[:error]}"
      end
    end

    if failure_count.positive?
      puts "\nFailures:"
      failed.each do |f|
        puts "  ✗ #{f[:file]}"
        puts "    #{f[:error]}"
      end
      unexpectedly_renderable.each do |file|
        puts "  ✗ #{file}"
        puts "    listed as known unrenderable but rendered successfully"
      end
      raise ValidationFailed, "validation failed: #{failed.size} failing, " \
                             "#{unexpectedly_renderable.size} unexpectedly renderable"
    else
      puts "\n✅ All renderable examples validated successfully!"
    end
  end

  # Literal children, never a glob. A directory legitimately named `g*` is a
  # pattern to Dir.glob, so the sweep matched a sibling's files and paired
  # them with the wrong directory. Nothing here needs pattern matching.
  #
  # @return [Array<String>] the entries of dir, as full paths
  # @raise [SystemCallError] if dir cannot be read — a folder that cannot be
  #   listed must not look like an empty one
  def children(dir)
    Dir.children(dir).sort.map { |entry| File.join(dir, entry) }
  end

  # A real directory, not a link to one. A link is skipped rather than
  # followed: it resolves somewhere this task has no claim on, and following
  # one is how pruning reached a fixture two levels down.
  def plain_directory?(path)
    File.directory?(path) && !File.symlink?(path)
  end

  def plain_svg?(path)
    path.end_with?('.svg') && File.file?(path) && !File.symlink?(path)
  end

  # One predicate for both callers. Generation used File.file? and the orphan
  # pairing used File.exist?, so a .mmd link to a directory was invisible to
  # one and a source to the other: the SVG beside it could never be pruned.
  def plain_mmd?(path)
    path.end_with?('.mmd') && File.file?(path) && !File.symlink?(path)
  end

  # The one place a diagram directory's sources are listed. :generate walks
  # this per directory; :validate flattens it across all of them -- both need
  # the same skip of a symlinked .mmd, so both call this rather than each
  # writing out children(dir).select { plain_mmd? } on its own.
  def mmd_files_in(dir)
    children(dir).select { |path| plain_mmd?(path) }
  end

  # The examples folder itself must be a real directory. A link there is
  # resolved by realpath and then trusted, so every containment check below
  # would be measuring against somewhere else entirely.
  # Serialises everything that WRITES to the examples tree.
  #
  # `prune_orphan_svgs` decided what to delete, then deleted it, and between
  # those two steps a source could be restored and its SVG regenerated -- the
  # delete still removed the fresh file. Re-deciding closer to the delete
  # narrows that window; it does not close it, because there is no atomic
  # "delete only if still an orphan" on a POSIX filesystem.
  #
  # So generate and prune take the same lock instead, and cannot interleave.
  # The lock is `flock` on a file in the system temp directory, keyed by the
  # examples root. Do not lock the root directory itself: Windows refuses to
  # open a directory (Errno::EISDIR). A lock file inside the tree would need
  # ignoring and could be mistaken for an example.
  def with_examples_lock(examples_dir)
    root = verified_root(examples_dir)
    return yield unless File.directory?(root)

    File.open(examples_lock_path(root), File::RDWR | File::CREAT, 0o644) do |handle|
      handle.flock(File::LOCK_EX)
      yield
    end
  end

  def examples_lock_path(root)
    key = Digest::SHA256.hexdigest(File.realpath(root))
    File.join(Dir.tmpdir, "sirena-examples-#{key}.lock")
  end

  # Copies each diagram directory's SVGs into docs_assets_dir with the same
  # literal-children and no-link predicates generation and pruning use, so a
  # link inside examples/ never pulls in files from outside it.
  #
  # The destination gets the same treatment, in the other direction: a
  # pre-existing entry named after a diagram type that is itself a symlink
  # would make `FileUtils.mkdir_p` see "already a directory" and do nothing,
  # then `FileUtils.cp` would follow it and write the SVG through the link to
  # wherever it points. Reproduced before this guard existed: a symlink at
  # docs_assets_dir/flowchart pointing outside the repo received the copied
  # SVG instead of docs_assets_dir itself.
  #
  # A guard-then-act pair like that is not enough on its own, even once both
  # halves are individually correct: `create_real_directory`/`manageable?`
  # below only decide what to do at the moment they run, and `FileUtils.cp`
  # opens whatever name it is given at the moment IT runs, which can be a
  # different moment. Something else with write access to docs_assets_dir
  # during this task's run window -- a concurrent process, not a remote
  # input -- can swap a symlink into target_dir or a leaf name in the gap
  # between the check and the write. Reproduced by deterministically racing
  # both gaps against the real code: a symlink swapped into target_dir
  # between the check and `FileUtils.mkdir_p` put every SVG for that type
  # into the attacker's directory instead (`mkdir_p` no-ops on "already
  # exists", symlink included); a symlink swapped into a leaf destination
  # between the partition check and `FileUtils.cp` overwrote the file it
  # pointed to outside docs_assets_dir, with the task still reporting
  # success. `write_svg` below already closes this exact shape of race for
  # generation, with a temporary-file-plus-rename pattern: `Dir.mkdir` and
  # `File.rename` are each one syscall that either succeeds cleanly or fails
  # outright on anything already at that name, including a symlink planted a
  # moment before -- neither one ever writes through an existing entry the
  # way `mkdir_p`/`cp` do. `create_real_directory` and `copy_through_rename`
  # below apply that same pattern here, so nothing raced into place between
  # a guard and its matching write can redirect either one.
  #
  # That closes the race for each INDIVIDUAL leaf operation, but not for the
  # PATH COMPONENTS the loop below keeps re-resolving by name across many
  # such operations. `verified_root`/`create_real_directory` confirm
  # docs_assets_dir once, at the top; every later `Dir.mkdir`/`File.rename`
  # for every diagram type still re-resolved "docs_assets_dir/<type>" by
  # walking that name fresh, so a concurrent process swapping docs_assets_dir
  # itself for a symlink after the one check at the top -- or swapping a
  # single type's target_dir for a symlink partway through ITS OWN per-file
  # loop, after target_dir's own one-time check -- redirected every operation
  # from that point on. Confirmed by execution (Codex round 3, HANDOFF 7):
  # racing a symlink into target_dir between the second and third SVG of a
  # loop that had already copied the first two normally sent the rest into
  # the attacker's directory, with the task still reporting success.
  #
  # `within_pinned_directory` below closes that: `Dir.chdir` resolves its
  # argument to a specific directory once, and the kernel then tracks the
  # process's current directory by that directory's own identity, not by
  # re-resolving the path string -- so every RELATIVE name used after it
  # (never one rejoined with the outer path) stays pinned to the same
  # physical directory for as long as the block runs, regardless of what the
  # outer name is renamed to or replaced with meanwhile. Verified directly:
  # renaming the directory a chdir'd process is inside of, and replacing its
  # old name with a symlink to an attacker directory, left every relative
  # write still landing in the original directory and the attacker directory
  # empty. `Dir.chdir` itself still has to resolve the name once to enter it,
  # the same single-syscall-wide gap `create_real_directory` already accepts
  # for the same reason (no POSIX primitive makes "verify, then use" one
  # step) -- so this pins by directory IDENTITY (device + inode, captured
  # right before the chdir and re-checked right after) rather than trusting
  # the chdir succeeded into the place expected, and raises instead of
  # proceeding on a mismatch. Verified directly: swapping the symlink in
  # during that one-syscall gap is reliably caught, and aborts with nothing
  # written to the attacker directory. A fully closed guarantee -- pinning
  # BEFORE any name lookup at all -- needs a directory file descriptor
  # opened first and directory-relative syscalls after (`openat`/`mkdirat`/
  # `renameat`), which Ruby's stdlib does not expose portably; reaching them
  # needs an FFI call to raw libc (`Fiddle`), which is not portable to
  # Windows either -- this PR's whole target platform. Applied at two
  # nesting levels below: once for docs_assets_dir across the whole method
  # (closing the docs_assets_dir-level race), and once per diagram type
  # inside it (closing the target_dir-level race for that type's own loop).
  #
  # Not wrapped in `with_examples_lock`: that lock only serializes this
  # gem's OWN generate/prune tasks against each other and buys nothing
  # against an external actor, which is the threat model above. It is
  # applied at the rake task level below anyway, for the same reason
  # generate/prune take it -- so this method cannot read examples_dir mid
  # regeneration by another of this gem's own tasks.
  #
  # `Dir.chdir` is process-wide and documented as not thread-safe against
  # OTHER code running in the same process. Acceptable here because this
  # whole module only ever runs as a single rake task's own CLI process --
  # `lib/tasks/examples.rake` is loaded by the Rakefile alone
  # (`Dir.glob('lib/tasks/**/*.rake').each { |r| load r }`), never
  # `require`d by `lib/sirena.rb`, so it never runs as library code inside a
  # caller's own multi-threaded application.
  #
  # @return [Array<Array(String, Integer)>] diagram type and count copied
  def copy_to_docs(examples_dir, docs_assets_dir)
    verified_root(docs_assets_dir, label: 'docs assets root')
    create_real_directory(docs_assets_dir, label: 'docs assets root')

    dirs = children(verified_root(examples_dir)).select { |path| plain_directory?(path) }
    work = dirs.filter_map do |dir|
      svg_files = children(dir).select { |path| plain_svg?(path) }
      svg_files.empty? ? nil : [File.basename(dir), svg_files]
    end

    within_pinned_directory(docs_assets_dir, label: 'docs assets root') do
      work.filter_map { |type, svg_files| copy_type_into_pinned_docs_root(type, svg_files) }
    end
  end

  # Runs entirely relative to the CALLER's pin on docs_assets_dir (see
  # `copy_to_docs` above) -- `type` and every destination below are bare
  # names, never rejoined with docs_assets_dir's own path, so nothing here
  # can be redirected by whatever that outer name is later changed to.
  def copy_type_into_pinned_docs_root(type, svg_files)
    if File.symlink?(type)
      puts "  ⚠️  skipped #{type}, its docs target is a symlink"
      return nil
    end

    create_real_directory(type, label: "docs target for #{type}")

    copied = within_pinned_directory(type, label: "docs target for #{type}") do
      svg_files.count do |svg_file|
        destination = File.basename(svg_file)
        unless manageable_relative?(destination)
          puts "  ⚠️  skipped #{type}/#{destination}, " \
               'its docs copy target is a symlink or already exists as something other than a plain file'
          next false
        end

        copy_through_rename(svg_file, destination)
        true
      end
    end

    [type, copied]
  end

  # The device+inode pair identifying the real filesystem object PATH names
  # right now -- not the path string itself, which is exactly what a
  # concurrent rename/symlink-swap can change out from under a name without
  # changing what a process already inside it is pinned to. Used by
  # `within_pinned_directory` to detect (not prevent -- see its comment) a
  # swap in the one-syscall gap between checking a name and entering it.
  def directory_identity(path, label:)
    stat = File.lstat(path)
    raise "#{label} is not a directory: #{path}" unless stat.directory?

    [stat.dev, stat.ino]
  end

  # Enters PATH by its filesystem identity, not by trusting its name still
  # points at the same place by the time the block runs. See `copy_to_docs`
  # above for why this exists and what it does and does not close.
  def within_pinned_directory(path, label:)
    expected_identity = directory_identity(path, label: label)

    Dir.chdir(path) do
      actual_identity = directory_identity('.', label: label)
      if actual_identity != expected_identity
        raise "#{label} changed identity between verification and use: #{path}"
      end

      yield
    end
  end

  # Same question `manageable?` below answers, for a NAME already relative
  # to an `within_pinned_directory` pin rather than an absolute path under
  # some root: containment is not a separate question here (the pin already
  # guarantees that), only whether the name itself is safe to write through
  # -- not a symlink, and not something other than a plain file already
  # sitting there.
  def manageable_relative?(name)
    return false if File.symlink?(name)

    !File.exist?(name) || File.lstat(name).file?
  end

  # One syscall that either creates a fresh real directory or fails outright
  # on anything already at that name -- unlike `FileUtils.mkdir_p`, which
  # treats "already exists" as success without asking what kind of thing it
  # is, including a symlink. The ordinary, expected case (this task has run
  # here before, a real directory is already sitting at path) still has to
  # succeed silently, so `Errno::EEXIST` is not itself an error here: it is
  # only an error if what is actually at path, checked fresh via `lstat`
  # right after the syscall that found it, turns out not to be a plain real
  # directory. That check cannot be glued to the `Dir.mkdir` syscall itself
  # -- no POSIX primitive makes "create, or verify-and-accept an existing
  # real directory" one atomic step -- but it collapses the race window from
  # this whole method's run to the gap between one syscall and the next.
  #
  # `Dir.mkdir` alone is not recursive: a genuinely fresh checkout with no
  # docs/assets directory at all yet -- not an attack, the ordinary first
  # run -- raised a raw Errno::ENOENT here instead of creating the tree, a
  # real regression caught by execution before this comment existed.
  # `FileUtils.mkdir_p` on the PARENT restores that, and does not reopen the
  # race this method exists to close: the parent was never the protected
  # leaf (every caller already walked it via `verified_root`'s ancestor
  # check, or -- for target_dir's parent, docs_assets_dir -- this same
  # method's own atomic creation one call earlier), and `Dir.mkdir` below
  # still owns path itself atomically regardless of how the parent came to
  # exist.
  def create_real_directory(path, label:)
    FileUtils.mkdir_p(File.dirname(path))
    Dir.mkdir(path)
  rescue Errno::EEXIST
    raise "#{label} became a symlink: #{path}" if File.lstat(path).symlink?
    raise "#{label} exists but is not a directory: #{path}" unless File.lstat(path).directory?
  end

  # Same shape as `write_svg` below, for the same reason: `FileUtils.cp`
  # opens destination and writes through whatever is already there,
  # including a symlink planted after `manageable?` cleared this call to
  # proceed. `File.rename` replaces the directory ENTRY at destination
  # atomically -- never the file a symlink there points to -- so whatever
  # raced into place between the guard and this call cannot redirect the
  # write; at worst it gets silently replaced by the real copy, same as an
  # ordinary rerun overwriting a previous one.
  def copy_through_rename(source, destination)
    temporary = File.join(File.dirname(destination), ".sirena-#{Process.pid}-#{SecureRandom.hex(8)}.tmp")
    created = false
    begin
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL) do |file|
        created = true
        IO.copy_stream(source, file)
      end
      File.rename(temporary, destination)
      created = false
    ensure
      FileUtils.rm_f(temporary) if created
    end
  end

  # The root itself must be a real directory with no symlinked ANCESTOR
  # either, not just not itself a link. A symlinked intermediate directory
  # (e.g. docs/assets -> outside the repo) passes a leaf-only check: the
  # literal path handed in is not itself a symlink, only reached through one.
  # Reproduced before this ancestor check existed: `docs/assets` symlinked
  # outside the repo left `docs/assets/examples` (an ordinary directory, just
  # reached through the symlinked ancestor) passing straight through, so
  # every write under it landed wherever `docs/assets` actually resolved.
  #
  # The ancestor walk is bounded to GEM_ROOT (see its comment) rather than
  # walked to filesystem `/`.
  #
  # The `start_with?` membership test below is a case-SENSITIVE string
  # comparison, which can under-match on a case-insensitive filesystem
  # (APFS and NTFS both default to this) if a caller ever hands in a path
  # differing only in case from GEM_ROOT's own recorded casing -- silently
  # skipping the whole ancestor walk rather than raising. Not reachable
  # through either rake task today: GEM_ROOT and every examples_dir/
  # docs_assets_dir this task is given are both built from the same
  # `__dir__` literal in one process, so their casing always agrees.
  # Verified by direct execution that a differently-cased root DOES skip the
  # walk; left as a known boundary rather than papered over with a
  # case-fold, which would be wrong on a case-SENSITIVE filesystem where two
  # differently-cased paths are genuinely different files. A future caller
  # that builds GEM_ROOT and its argument paths from different sources would
  # need to normalize casing itself before calling this.
  def verified_root(path, label: 'examples root')
    path = File.expand_path(path)
    raise "#{label} must not be a link: #{path}" if File.symlink?(path)

    if path == GEM_ROOT || path.start_with?("#{GEM_ROOT}#{File::SEPARATOR}")
      existing = path
      existing = File.dirname(existing) until File.exist?(existing)

      # Compared against GEM_ROOT's OWN resolution, not against the literal
      # path: GEM_ROOT itself may sit beneath a symlink this task has no
      # claim on (confirmed by execution -- macOS's Dir.mktmpdir routes
      # through /var -> private/var, and a checkout can legitimately sit
      # under a symlinked mount), which is not this task's business (see
      # GEM_ROOT's comment). Comparing the literal path against realpath
      # unconditionally made THIS check false-positive on exactly the kind
      # of path it must not: every nested directory under a GEM_ROOT that
      # itself resolves through any symlink, with no symlink actually
      # introduced below it. Only a symlink on the portion BELOW GEM_ROOT
      # (the part this task actually owns) is checked.
      real_gem_root = File.realpath(GEM_ROOT)
      suffix = existing == GEM_ROOT ? nil : existing.delete_prefix("#{GEM_ROOT}#{File::SEPARATOR}")
      expected = suffix ? File.join(real_gem_root, suffix) : real_gem_root
      if File.realpath(existing) != expected
        raise "#{label} sits beneath a symlinked directory: #{path}"
      end
    end

    path
  end

  # The two depths the gemspec packages and the conformance gate pairs: an
  # SVG directly under examples/ and one beside its source in a diagram
  # directory. A sweep one level deep missed the first kind, which is how the
  # two this branch removed were found; `**` went too far the other way and
  # reached a nested fixture tree that nothing here manages.
  def managed_svgs(examples_dir)
    entries = children(verified_root(examples_dir))
    top = entries.select { |path| plain_svg?(path) }
    nested = entries.select { |path| plain_directory?(path) }
      .flat_map { |dir| children(dir).select { |path| plain_svg?(path) } }
    top + nested
  end

  # Where a path is allowed to be, judged on its DIRECTORY rather than on
  # itself: the file may not exist yet, and a symlinked file has to be judged
  # by where it sits, not by where it points.
  def within?(root, path)
    root = File.realpath(root)
    directory = File.realpath(File.dirname(path))
    directory == root || directory.start_with?("#{root}#{File::SEPARATOR}")
  rescue Errno::ENOENT
    false
  end

  # A path this task may write to or delete. Containment is not enough on its
  # own: a symlink sitting inside examples/ passes the directory test and
  # still resolves somewhere else, so writing through it would overwrite a
  # file outside the tree and deleting it would only remove the link.
  def manageable?(root, path)
    return false if File.symlink?(root)
    return false unless within?(root, path)
    return false if File.symlink?(path)

    # An existing entry that is not a plain file — a FIFO, a socket, a
    # directory — is not something this task created. File.rename replaces
    # a FIFO or socket silently; against a directory it raises Errno::EISDIR
    # instead. Either way this refuses it up front with one clear,
    # deliberate error rather than a silent replacement or an OS error
    # surfacing from inside a write.
    !File.exist?(path) || File.lstat(path).file?
  end

  # An SVG whose source is gone still ships: git tracks it and the gemspec
  # packages it, and the generate loop walks sources, so nothing ever visits
  # it. It has to go — but nothing here can tell a stale generated SVG from
  # one a human wrote, because Sirena stamps no provenance into its output.
  #
  # So generation REPORTS them and `rake examples:prune` deletes them. A
  # routine regeneration can no longer destroy a file it did not create; the
  # conformance gate still fails on an orphan, which is what sends a human to
  # the prune task deliberately.
  def orphan_svgs(examples_dir)
    managed_svgs(examples_dir)
      .reject { |svg| plain_mmd?(svg.sub(/\.svg\z/, '.mmd')) }
      .select { |svg| manageable?(examples_dir, svg) }
      .sort
  end

  def report_orphan_svgs(examples_dir)
    orphans = orphan_svgs(examples_dir)
    return if orphans.empty?

    puts "\n\u26a0\ufe0f  #{orphans.size} SVG(s) have no source and are still packaged:"
    orphans.each { |svg| puts "    #{svg.sub("#{examples_dir}/", '')}" }
    puts "   Run 'rake examples:prune' to delete them."
  end

  def prune_orphan_svgs(examples_dir)
    removed = 0
    orphan_svgs(examples_dir).each do |svg_file|
      # Re-decided here, not trusted from the list above. The lock makes an
      # interleaved `generate` impossible; this also covers a source restored
      # by hand, which no lock of ours can serialise.
      next unless still_orphaned?(examples_dir, svg_file)

      File.delete(svg_file)
      removed += 1
      puts "    removed #{svg_file.sub("#{examples_dir}/", '')}, which no longer has a source"
    end
    removed
  end

  # Whether SVG_FILE is STILL an orphan at this instant, rather than at the
  # moment the list was built.
  def still_orphaned?(examples_dir, svg_file)
    orphan_svgs(examples_dir).include?(svg_file)
  end

  # The SVG beside a source EXPECTED_UNRENDERABLE_SOURCES names. Such a source
  # never renders, so any SVG still sitting beside it is a leftover from
  # before the source was added to that list — stale in exactly the way an
  # orphan is, just with its .mmd still present, so orphan_svgs' "no source"
  # test does not catch it.
  def known_unrenderable_svgs(examples_dir)
    root = verified_root(examples_dir)
    EXPECTED_UNRENDERABLE_SOURCES
      .map { |source| File.join(root, source.sub(/\.mmd\z/, '.svg')) }
      .select { |svg| plain_svg?(svg) }
      .select { |svg| manageable?(examples_dir, svg) }
      .sort
  end

  def prune_known_unrenderable_svgs(examples_dir)
    stale = known_unrenderable_svgs(examples_dir)
    stale.each do |svg_file|
      File.delete(svg_file)
      puts "    removed #{svg_file.sub("#{examples_dir}/", '')}, beside a source that never renders"
    end
    stale.size
  end

  # Raised rather than exiting the process: this is a plain library method a
  # caller can require and call directly, and only a script's entry point may
  # decide a process exit status.
  class UnexpectedRenderFailure < StandardError; end

  # `exit` in a plain method kills the caller's whole process, so only the
  # rake task below may decide an exit status.
  class ValidationFailed < StandardError; end

  # A source that stops rendering must not keep shipping its old SVG looking
  # still valid. But :generate runs concurrently with nothing standing guard,
  # so deleting HERE is exactly the write this run cannot prove is safe: three
  # rounds of guards (a SystemCallError re-raise, an mtime check, moving
  # metadata reads outside the rescue) each closed one race and opened
  # another — a paused run's stale mtime check firing after a concurrent
  # writer's fresh SVG, and a sidecar failure elsewhere still reaching this
  # path. The capability is removed rather than guarded a fourth time: this
  # method only reports, so nothing under :generate can delete a file it did
  # not just write. Deleting the stale SVG is `rake examples:prune`'s job — a
  # deliberate, standalone run with no concurrent writer to race.
  def handle_failed_svgs(failed_renders, examples_dir)
    unexpected_sources = failed_renders.map(&:first) - EXPECTED_UNRENDERABLE_SOURCES
    unless unexpected_sources.empty?
      puts "\n⚠️  Unexpected render failure: example sources failed to render."
      puts "   Unexpected: #{unexpected_sources.sort.join(', ')}; SVGs that did render have " \
           "already been rewritten, while nothing was deleted."
      raise UnexpectedRenderFailure, "unexpected render failure: #{unexpected_sources.sort.join(', ')}"
    end

    stale = failed_renders.map(&:last).select { |svg_file| File.exist?(svg_file) }
    return if stale.empty?

    puts "\n⚠️  #{stale.size} SVG(s) no longer render and are still packaged:"
    stale.each { |svg_file| puts "    #{svg_file.delete_prefix("#{examples_dir}/")}" }
    puts "   Run 'rake examples:prune' to delete them."
  end

  # A render that produced no document must not destroy the document already
  # there. `File.write` truncates before it writes, so handing it a nil render
  # left a zero-byte SVG that the loop then counted as generated, and a write
  # that died partway left the old file truncated.
  #
  # Rendered into a sibling temporary file and renamed into place, so the
  # visible file only ever changes as a whole, and refused outright unless the
  # render actually looks like an SVG document.
  # An SVG document, not a string that merely mentions one: an error page
  # carrying an inline <svg> passed a substring check and replaced a good
  # picture with itself. The whole start tag has to be there: matching one
  # character after the name accepted `<svg/garbage` and `<svg width="1"`,
  # and write_svg replaced a good picture with the first of those.
  def svg_document?(svg)
    svg.is_a?(String) &&
      svg.match?(%r{\A\s*(?:<\?xml[^>]*\?>\s*)?(?:<!--.*?-->\s*)*<svg(?:\s[^>]*)?/?>}m)
  end

  def write_svg(svg_file, svg, examples_dir)
    raise "refused an unsafe SVG target: #{svg_file}" unless manageable?(examples_dir, svg_file)
    raise 'rendered no SVG document' unless svg_document?(svg)

    # Independent of the target's basename: embedding a legal 255-byte name
    # produced an illegal temporary one and ENAMETOOLONG.
    temporary = File.join(File.dirname(svg_file),
                          ".sirena-#{Process.pid}-#{SecureRandom.hex(8)}.tmp")
    created = false
    begin
      # CREAT|EXCL rather than File.write: the temporary path is predictable,
      # and File.write follows whatever is already there. Anything sitting on
      # that name — a leftover from a killed run, or a link — must abort the
      # write rather than be written through onto its target.
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL) do |file|
        created = true
        file.write(svg)
      end
      File.rename(temporary, svg_file)
      # Renamed, so the temporary name is vacant. Leaving `created` set made
      # the ensure below unlink whatever next claimed that name.
      created = false
    ensure
      # Only what this call made. Removing a name we refused to write to would
      # be the same mistake one step down.
      FileUtils.rm_f(temporary) if created
    end
  end

  # Takes the root as an argument so a test can drive the real task against a
  # throwaway tree. A destructive task nobody can run in a sandbox is a task
  # nobody can prove.
  def generate_examples(examples_dir)
    total_generated = 0
    failed_renders = []

    diagram_dirs(examples_dir).each do |dir|
      diagram_type = File.basename(dir)
      puts "\n\u{1F4CA} Generating examples for #{diagram_type}..."
      mmd_files = mmd_files_in(dir)

      if mmd_files.empty?
        puts "  \u26a0\ufe0f  No examples found for #{diagram_type}"
        next
      end

      mmd_files.each do |mmd_file|
        basename = File.basename(mmd_file, '.mmd')
        # From the source path, not rebuilt from the directory: a directory
        # named with glob syntax made those two disagree.
        svg_file = mmd_file.sub(/\.mmd\z/, '.svg')
        # Read outside the render-failure rescue below: a malformed .yml is a
        # metadata problem, not evidence the source fails to render, and
        # folding it into failed_renders gave a bad .yml on an allowlisted
        # source the same deletion permission as a genuine render failure.
        theme = theme_for(mmd_file)

        begin
          svg = Sirena.render(File.read(mmd_file), theme: theme, today: EXAMPLE_TODAY)
          write_svg(svg_file, svg, examples_dir)
          puts "  \u2713 #{basename}.svg"
          total_generated += 1
        rescue SystemCallError
          # An I/O failure, not a render failure: the OS refused the write
          # itself (a full disk, Errno::EFBIG), and the source may render
          # perfectly well. Folding this into the render-failure rescue
          # below let handle_failed_svgs mistake it for the source failing
          # to render, and for an allowlisted source that meant deleting the
          # previous good SVG on the strength of a write failure. This must
          # abort the task instead, the same way an unreadable diagram
          # directory already does (see 'refusing what it did not create').
          raise
        rescue StandardError => e
          puts "  \u2717 #{basename}.svg - ERROR: #{e.message}"
          failed_renders << [mmd_file.delete_prefix("#{examples_dir}/"), svg_file]
        end
      end
    end

    report_orphan_svgs(examples_dir)
    [total_generated, failed_renders]
  end

  # A symlinked diagram directory resolves outside examples/, and the loop
  # would then write and delete there while reporting success. Skipped by
  # name so the run says which one it refused.
  #
  # Checked before File.directory?, not after: File.directory? follows a
  # symlink to judge its TARGET, so a dangling one (pointing nowhere) failed
  # that check first and fell out silently below with no warning at all --
  # unlike a symlink that resolves to a real directory, which reached the
  # warning. Both are refused; only a dangling one was refused silently.
  def diagram_dirs(examples_dir)
    children(verified_root(examples_dir)).select do |entry|
      name = File.basename(entry)
      next false if name.start_with?('.')

      if File.symlink?(entry)
        puts "  \u26a0\ufe0f  skipped #{name}, a symlinked directory that leaves examples/"
        next false
      end
      next false unless File.directory?(entry)

      true
    end
  end
end

namespace :examples do
  desc "Generate all example SVGs from source files"
  task :generate do
    require 'sirena'
    require 'yaml'
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)

    unless Dir.exist?(examples_dir)
      puts "⚠️  Examples directory not found: #{examples_dir}"
      puts "Run 'rake examples:init' to create the directory structure"
      exit 1
    end

    total_generated, failed_renders =
      ExampleTasks.with_examples_lock(examples_dir) do
        ExampleTasks.generate_examples(examples_dir)
      end

    begin
      ExampleTasks.handle_failed_svgs(failed_renders, examples_dir)
    rescue ExampleTasks::UnexpectedRenderFailure
      exit 1
    end
    puts "\n" + "=" * 60
    puts "✅ Example generation complete!"
    puts "   Generated: #{total_generated}"
    puts "   Failed: #{failed_renders.size}"
    puts "=" * 60
  end

  desc "Delete example SVGs whose source is gone or never renders (destructive, deliberate)"
  task :prune do
    examples_dir = File.expand_path('../../examples', __dir__)

    ExampleTasks.with_examples_lock(examples_dir) do
      puts "Pruning example SVGs with no source..."
      removed = ExampleTasks.prune_orphan_svgs(examples_dir)
      puts removed.zero? ? "Nothing to prune." : "Removed #{removed} orphaned SVG(s)."

      puts "\nPruning example SVGs beside a source that never renders..."
      removed = ExampleTasks.prune_known_unrenderable_svgs(examples_dir)
      puts removed.zero? ? "Nothing to prune." : "Removed #{removed} stale SVG(s)."
    end
  end

  desc "Copy generated examples to docs/assets/examples"
  task :copy_to_docs do
    examples_dir = File.expand_path('../../examples', __dir__)
    docs_assets_dir = File.expand_path('../../docs/assets/examples', __dir__)

    # No pre-creation of docs_assets_dir here: ExampleTasks.copy_to_docs
    # creates it itself, AFTER its own verified_root guard runs, not before.
    # Creating it here first (as this task used to) meant `FileUtils.mkdir_p`
    # would walk through a symlinked ancestor and leave a real, empty
    # directory outside the repo even when the guard went on to abort the
    # task for exactly that ancestor -- reproduced by execution: a symlink at
    # docs/assets left `outside_target/examples` created before the guard
    # ever ran.
    copied = ExampleTasks.with_examples_lock(examples_dir) do
      ExampleTasks.copy_to_docs(examples_dir, docs_assets_dir)
    end
    copied.each do |diagram_type, count|
      puts "✓ Copied #{count} #{diagram_type} examples to docs/assets/examples/"
    end

    puts "\n✅ #{copied.sum { |_, count| count }} examples copied to documentation!"
  end

  desc "Generate AsciiDoc include files for documentation"
  task :generate_docs do
    require 'yaml'
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)
    docs_examples_dir = File.expand_path('../../docs/_diagram_types/examples', __dir__)

    FileUtils.mkdir_p(docs_examples_dir)

    diagram_dirs = Dir.glob(File.join(examples_dir, '*')).select { |f| File.directory?(f) }

    diagram_dirs.sort.each do |dir|
      diagram_type = File.basename(dir)
      next if diagram_type == '.git' || diagram_type.start_with?('.')

      mmd_files = Dir.glob(File.join(dir, '*.mmd')).sort
      next if mmd_files.empty?

      # Generate AsciiDoc include file
      adoc_file = File.join(docs_examples_dir, "#{diagram_type}-examples.adoc")

      content = []
      content << "// Auto-generated examples for #{diagram_type}"
      content << "// Generated by rake examples:build"
      content << ""

      mmd_files.each_with_index do |mmd_file, index|
        basename = File.basename(mmd_file, '.mmd')
        yml_file = File.join(dir, "#{basename}.yml")

        # Read metadata
        metadata = File.exist?(yml_file) ? YAML.load_file(yml_file) : {}
        title = metadata['title'] || basename.split('-').map(&:capitalize).join(' ')
        description = metadata['description'] || 'Example diagram'
        complexity = metadata['complexity'] || 'basic'
        use_cases = metadata['use_cases'] || []

        content << "==== Example #{index + 1}: #{title}"
        content << ""
        content << ".#{description}"

        if !use_cases.empty? || complexity != 'basic'
          content << "[NOTE]"
          content << "===="
          content << "Complexity: #{complexity.capitalize}"
          if !use_cases.empty?
            content << " +"
            content << "Use Cases: #{use_cases.join(', ')}"
          end
          content << "===="
        end

        content << ""
        content << ".Source Code"
        content << "[source,mermaid]"
        content << "----"
        content << File.read(mmd_file).strip
        content << "----"
        content << ""
        content << ".Rendered Output"
        content << "image::../../assets/examples/#{diagram_type}/#{basename}.svg[#{title},600]"
        content << ""
        content << "'''"
        content << ""
      end

      File.write(adoc_file, content.join("\n"))
      puts "✓ Generated #{diagram_type}-examples.adoc (#{mmd_files.size} examples)"
    end

    puts "\n✅ Documentation includes generated!"
  end

  desc "Validate all examples (parse and render)"
  task :validate do
    require 'sirena'
    require 'yaml'

    examples_dir = File.expand_path('../../examples', __dir__)
    begin
      ExampleTasks.validate_examples(examples_dir)
    rescue ExampleTasks::ValidationFailed => e
      warn e.message
      exit 1
    end
  end

  desc "Generate all examples and copy to docs"
  task :build => [:generate, :generate_docs, :copy_to_docs]

  desc "Create example template for a diagram type"
  task :create, [:type, :name] do |t, args|
    require 'fileutils'

    type = args[:type]
    name = args[:name]

    if type.nil? || name.nil?
      puts "Usage: rake examples:create[type,name]"
      puts "Example: rake examples:create[flowchart,basic-flow]"
      exit 1
    end

    examples_dir = File.expand_path('../../examples', __dir__)
    type_dir = File.join(examples_dir, type)

    FileUtils.mkdir_p(type_dir)

    # Find next number
    existing = Dir.glob(File.join(type_dir, '*.mmd')).map do |f|
      File.basename(f).split('-').first.to_i
    end.max || 0
    number = existing + 1

    basename = format("%02d-%s", number, name)

    # Create .mmd file
    mmd_file = File.join(type_dir, "#{basename}.mmd")
    File.write(mmd_file, "#{type}\n  A --> B\n")

    # Create .yml file
    yml_file = File.join(type_dir, "#{basename}.yml")
    yml_content = <<~YAML
      title: "#{name.split('-').map(&:capitalize).join(' ')}"
      description: "Description of this example"
      complexity: basic
      keywords:
        - #{type}
      use_cases:
        - "Example use case"
      theme: default
    YAML
    File.write(yml_file, yml_content)

    puts "✓ Created #{basename}.mmd"
    puts "✓ Created #{basename}.yml"
    puts "\nEdit these files and run: rake examples:generate"
  end

  desc "List all examples with status"
  task :list do
    require 'yaml'

    examples_dir = File.expand_path('../../examples', __dir__)

    unless Dir.exist?(examples_dir)
      puts "Examples directory not found: #{examples_dir}"
      puts "Run 'rake examples:init' to create it"
      exit 1
    end

    diagram_dirs = Dir.glob(File.join(examples_dir, '*')).select { |f| File.directory?(f) }

    total_examples = 0

    diagram_dirs.sort.each do |dir|
      diagram_type = File.basename(dir)
      next if diagram_type == '.git' || diagram_type.start_with?('.')

      examples = Dir.glob(File.join(dir, '*.mmd'))
      total_examples += examples.size

      puts "\n#{diagram_type.upcase.tr('-', ' ')} (#{examples.size} examples)"
      puts "─" * 60

      if examples.empty?
        puts "  (no examples yet)"
        next
      end

      examples.sort.each do |mmd_file|
        basename = File.basename(mmd_file, '.mmd')
        yml_file = File.join(dir, "#{basename}.yml")
        svg_file = File.join(dir, "#{basename}.svg")

        metadata = File.exist?(yml_file) ? YAML.load_file(yml_file) : {}
        title = metadata['title'] || basename
        complexity = metadata['complexity'] || 'basic'

        svg_status = File.exist?(svg_file) ? "✓" : "✗"

        puts "  #{svg_status} #{basename}: #{title} [#{complexity}]"
      end
    end

    puts "\n" + "=" * 60
    puts "Total: #{total_examples} examples across #{diagram_dirs.size} diagram types"
    puts "=" * 60
  end

  desc "Initialize examples directory structure"
  task :init do
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)

    # Create main examples directory
    FileUtils.mkdir_p(examples_dir)

    # Create README
    readme_content = <<~README
      # Sirena Examples

      This directory contains example diagrams for all supported diagram types.

      ## Structure

      Each diagram type has its own directory with:
      - `*.mmd` - Mermaid source files
      - `*.yml` - Metadata for each example
      - `*.svg` - Rendered output, regenerated in place and committed

      ## Usage

      ```bash
      # Generate all SVGs
      rake examples:generate

      # Create a new example
      rake examples:create[flowchart,my-example]

      # Validate all examples
      rake examples:validate

      # List all examples
      rake examples:list

      # Build everything (generate + docs + copy)
      rake examples:build
      ```

      ## Adding Examples

      1. Create example files:
         ```bash
         rake examples:create[type,name]
         ```

      2. Edit the `.mmd` and `.yml` files

      3. Generate SVG:
         ```bash
         rake examples:generate
         ```

      4. Build documentation:
         ```bash
         rake examples:build
         ```

      ## Example Metadata

      Each `.yml` file should contain:

      ```yaml
      title: "Example Title"
      description: "What this example demonstrates"
      complexity: basic  # basic, intermediate, advanced
      keywords:
        - keyword1
        - keyword2
      use_cases:
        - "Use case description"
      theme: default  # default, dark, light, high-contrast
      ```
    README

    File.write(File.join(examples_dir, 'README.md'), readme_content)

    # Create .gitignore
    gitignore_content = <<~GITIGNORE
      # Stale generated/ directories from older checkouts. Nothing writes them
      # now — the shipped SVGs sit beside their sources — but leaving the rule
      # keeps an old working copy quiet and stops `git add examples/` sweeping
      # stale output back in.
      */generated/

      # Ignore macOS files
      .DS_Store

      # Ignore editor files
      *.swp
      *.swo
      *~
    GITIGNORE

    File.write(File.join(examples_dir, '.gitignore'), gitignore_content)

    puts "✓ Created examples/ directory"
    puts "✓ Created README.md"
    puts "✓ Created .gitignore"
    puts "\n✅ Examples directory initialized!"
    puts "\nNext steps:"
    puts "  1. Create examples: rake examples:create[type,name]"
    puts "  2. Generate SVGs: rake examples:generate"
    puts "  3. Build docs: rake examples:build"
  end

  desc "Clean stale generated directories and documentation copies"
  task :clean do
    require 'fileutils'

    examples_dir = File.expand_path('../../examples', __dir__)
    docs_assets_dir = File.expand_path('../../docs/assets/examples', __dir__)
    docs_examples_dir = File.expand_path('../../docs/_diagram_types/examples', __dir__)

    # Clean the stale generated/ directories older checkouts left behind.
    # The shipped SVGs sit beside their sources now and are not touched.
    Dir.glob(File.join(examples_dir, '*/generated')).each do |dir|
      FileUtils.rm_rf(dir)
      puts "✓ Removed #{dir}"
    end

    # Clean docs assets
    if Dir.exist?(docs_assets_dir)
      FileUtils.rm_rf(docs_assets_dir)
      puts "✓ Removed #{docs_assets_dir}"
    end

    # Clean docs includes
    if Dir.exist?(docs_examples_dir)
      FileUtils.rm_rf(docs_examples_dir)
      puts "✓ Removed #{docs_examples_dir}"
    end

    puts "\n✅ Cleaned stale generated directories and documentation copies!"
  end
end
