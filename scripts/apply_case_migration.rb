#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "tempfile"
require "yaml"

# Applies config/corpus_case_migration.json to a repository: renames every
# case's files, then rewrites every reference to the old name.
#
#   ruby scripts/apply_case_migration.rb --dry-run [--summary]
#   ruby scripts/apply_case_migration.rb --apply
#   ruby scripts/apply_case_migration.rb --verify
#
# The type directory never changes; only the file name does
# (`pie/001_a_0.mmd` becomes `pie/<slug>-<hash8>.mmd`), so a reference is
# rewritten by swapping the name wherever it appears: a full case key, a
# `spec/mermaid/...` path, a `spec/fixtures_mermaid/<dir>/[correct/]...` path
# or a bare name next to a separate type. Some old names occur in more than
# one type; those are resolved by the directory written just before the name,
# then by byte-identity with the case the line is about (Twins), and
# otherwise listed as unresolved. Apply refuses to start while anything is
# unresolved or a rename target is taken.
#
# The scope is every file git knows about (tracked, or untracked and not
# ignored) at run time, minus the manifest itself. A JSON, YAML or one-case-
# per-line text file that was sorted by case or reference before is sorted
# again afterwards, so the next regeneration shows no ordering diff.
#
# Apply writes in two phases (rewrites, then renames) after every check has
# passed. A crash between the phases leaves a dirty tree: recover with
# `git restore .` plus `git clean -fd` on the case directories.
module ApplyCaseMigration
  class Error < StandardError; end

  class ManifestError < Error; end

  class ConflictError < Error; end

  class DirtyTreeError < Error; end

  class UnresolvedError < Error; end

  MANIFEST = "config/corpus_case_migration.json"
  CORPUS = "spec/mermaid"
  OLD_PATTERN = %r{\A([a-z0-9_]+)/([\w-]+)\.mmd\z}
  NEW_PATTERN = %r{\A([a-z0-9_]+)/([\w-]+)\z}
  CASE_PATH = %r{\A[a-z0-9_]+/[^/\s]+\.mmd\z}
  # A name is a whole run of word characters and hyphens, so a longer name
  # that merely starts with an old one is never touched.
  TOKEN = /[\w-]+/
  HINT = %r{([A-Za-z0-9_]+)/(?:correct/)?\z}
  HINT_WINDOW = 80
  ORDERING_KEYS = %w[case reference].freeze
  REQUIRED_EXTENSIONS = %w[mmd meta.json].freeze

  # One old->new case: its type, and the old and new file stem.
  class Pair
    attr_reader :type, :old_base, :new_base

    def initialize(type:, old_base:, new_base:)
      @type = type
      @old_base = old_base
      @new_base = new_base
    end

    def old_id
      "#{type}/#{old_base}"
    end

    def new_id
      "#{type}/#{new_base}"
    end
  end

  # Finds the pair a name refers to. A name used by several types needs a
  # directory to choose between them.
  class Catalog
    attr_reader :pairs

    def initialize(pairs)
      @pairs = pairs
      @by_base = pairs.group_by(&:old_base)
    end

    def base?(name)
      @by_base.key?(name)
    end

    def types
      pairs.map(&:type).uniq
    end

    def candidates(base)
      @by_base.fetch(base)
    end

    def resolve(base, type)
      found = candidates(base)
      return found.first if found.one?

      found.find { |pair| pair.type == type }
    end

    def resolve_in(base, directories)
      return resolve(base, nil) if candidates(base).one?

      directories.reverse_each do |dir|
        pair = resolve(base, dir)
        return pair if pair
      end
      nil
    end
  end

  # Settles a name used by several types, written with no directory, by
  # byte-identity: `twin rendered: <name>` in a verdict entry names a case
  # whose source is identical to the entry's own, and exactly one of the
  # candidates is.
  class Twins
    def initialize(root)
      @root = root
      @digests = {}
    end

    def pick(candidates, context)
      return unless context

      same = candidates.select { |pair| digest(pair) == digest(context) }
      same.first if same.one?
    end

    private

    def digest(pair)
      @digests[pair] ||= Digest::SHA256.file(
        File.join(@root, CORPUS, pair.type, "#{pair.old_base}.mmd"),
      ).hexdigest
    end
  end

  # What apply would do: [from, to] renames, rewritten file contents, the
  # references it cannot resolve and the renames that cannot happen.
  class Plan
    attr_reader :moves, :rewrites, :unresolved, :conflicts, :manual

    def initialize(moves:, rewrites:, unresolved:, conflicts:, manual:)
      @moves = moves
      @rewrites = rewrites
      @unresolved = unresolved
      @conflicts = conflicts
      @manual = manual
    end

    def blocked?
      !(unresolved.empty? && conflicts.empty?)
    end

    def references
      rewrites.values.sum { |entry| entry[:count] }
    end
  end

  # Keeps a rewritten file in the order its generator would write it.
  module Ordering
    module_function

    # Returns [text, :plain | :structured | :unverified].
    def call(path, original, rewritten)
      case File.extname(path)
      when ".json" then structured(:json, original, rewritten)
      when ".yml", ".yaml" then structured(:yaml, original, rewritten)
      when ".txt" then lines(original, rewritten)
      else [rewritten, :plain]
      end
    end

    def structured(format, original, rewritten)
      before = parse(format, original)
      return [rewritten, :unverified] unless dump(format, before).b == original

      after = order_like(before, parse(format, rewritten))
      [dump(format, after), :structured]
    rescue JSON::ParserError, Psych::Exception, EncodingError, ArgumentError
      [rewritten, :unverified]
    end

    def lines(original, rewritten)
      before = original.split("\n")
      return [rewritten, :plain] unless listing?(before, original)

      after = rewritten.split("\n")
      after = after.sort if before == before.sort
      ["#{after.join("\n")}\n", :structured]
    end

    def listing?(list, original)
      !list.empty? && list.all? { |line| CASE_PATH.match?(line) } &&
        "#{list.join("\n")}\n" == original
    end

    def parse(format, text)
      text = text.dup.force_encoding(Encoding::UTF_8)
      return JSON.parse(text) if format == :json

      YAML.safe_load(text, aliases: false)
    end

    def dump(format, data)
      return "#{JSON.pretty_generate(data)}\n" if format == :json

      YAML.dump(data)
    end

    def order_like(before, after)
      case after
      when Hash then order_hash(before, after)
      when Array then order_array(before, after)
      else after
      end
    end

    def order_hash(before, after)
      pairs = after.each_with_index.map do |(key, value), index|
        [key, order_like(before.values[index], value)]
      end
      pairs.sort_by!(&:first) if sorted_keys?(before.keys)
      pairs.to_h
    end

    def order_array(before, after)
      items = after.each_with_index.map { |v, i| order_like(before[i], v) }
      return items unless sorted_keys?(before.map { |item| sort_key(item) })

      items.sort_by { |item| sort_key(item) }
    end

    def sorted_keys?(keys)
      keys.length > 1 && keys.all?(String) &&
        keys.all? { |key| key.include?("/") } && keys == keys.sort
    end

    def sort_key(item)
      return item if item.is_a?(String)
      return unless item.is_a?(Hash)

      ORDERING_KEYS.filter_map { |name| item[name] }.grep(String).first
    end

    private_class_method :structured, :lines, :listing?, :parse, :dump,
                         :order_like, :order_hash, :order_array,
                         :sorted_keys?, :sort_key
  end

  # Reads the manifest into Pairs.
  module Manifest
    module_function

    def pairs(root)
      text = File.read(File.join(root, MANIFEST))
      entries = JSON.parse(text).fetch("pairs")
      pairs = entries.map { |entry| pair(entry) }
      %i[new_base old_base].each { |field| reject_twice(pairs, field) }
      pairs
    rescue Errno::ENOENT, JSON::ParserError, KeyError => e
      raise ManifestError, "cannot read #{MANIFEST}: #{e.message}"
    end

    def pair(entry)
      old = OLD_PATTERN.match(entry["old"].to_s)
      new = NEW_PATTERN.match(entry["new"].to_s)
      raise ManifestError, "bad manifest entry #{entry.inspect}" unless
        old && new && old[1] == new[1]

      Pair.new(type: old[1], old_base: old[2], new_base: new[2])
    end

    def reject_twice(pairs, field)
      groups = pairs.group_by { |pair| [pair.type, pair.public_send(field)] }
      clash = groups.select { |_, group| group.length > 1 }.keys
      return if clash.empty?

      names = clash.map { |key| key.join("/") }.join(", ")
      raise ConflictError, "manifest lists #{field} twice: #{names}"
    end

    private_class_method :pair, :reject_twice
  end

  # The files a run looks at, and whether git considers the tree clean.
  module Tree
    module_function

    def clean?(root)
      out, status = Open3.capture2("git", "status", "--porcelain", chdir: root)
      raise Error, "git status failed in #{root}" unless status.success?

      out.empty?
    end

    def files(root)
      out, status = Open3.capture2(
        "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
        chdir: root
      )
      raise Error, "git ls-files failed in #{root}" unless status.success?

      out.split("\0").uniq.reject { |file| file == MANIFEST }
        .select { |file| plain_file?(File.join(root, file)) }
    end

    def plain_file?(full)
      File.file?(full) && !File.symlink?(full)
    end

    private_class_method :plain_file?
  end

  # Rewrites the old names in one file's bytes. A name found in a path with
  # a directory before it is resolved by that directory; the last such case
  # is the context a later bare name is matched against.
  class Rewriter
    attr_reader :unresolved

    def initialize(root, catalog)
      @catalog = catalog
      @twins = Twins.new(root)
      @unresolved = []
    end

    # { text:, count:, ordering: }, or nil when nothing in the file changed.
    def call(file, bytes)
      @file = file
      @bytes = bytes
      @count = 0
      @context = nil
      text = bytes.gsub(TOKEN) { replacement(Regexp.last_match) }
      return if @count.zero?

      ordered, ordering = Ordering.call(file, bytes, text)
      { text: ordered, count: @count, ordering: ordering }
    end

    private

    def replacement(match)
      name = match[0]
      return name unless @catalog.base?(name)

      pair = pair_for(name, match.begin(0))
      return left_alone(name, match.begin(0)) unless pair

      @count += 1
      pair.new_base
    end

    def pair_for(name, position)
      hint = @bytes[[position - HINT_WINDOW, 0].max...position][HINT, 1]
      pair = @catalog.resolve(name, hint)
      @context = pair if pair && hint
      pair || @twins.pick(@catalog.candidates(name), @context)
    end

    def left_alone(name, position)
      line = @bytes[0, position].count("\n") + 1
      @unresolved << "#{@file}:#{line} #{name} " \
                     "(used by several types, no directory given)"
      name
    end
  end

  # Rewrites every file in scope and lists ordinal-only mentions
  # (`type NNN`, `type/NNN...`) that no tool can rewrite.
  class Scan
    attr_reader :rewrites, :manual

    def initialize(root, catalog)
      @root = root
      @rewriter = Rewriter.new(root, catalog)
      types = catalog.types.sort_by { |type| -type.size }
      @ordinal = %r{(?<![\w-])(?:#{Regexp.union(types)})[ /]\d{3}(?![\w-])}
      @rewrites = {}
      @manual = []
    end

    def unresolved
      @rewriter.unresolved
    end

    def run(files)
      files.each { |file| visit(file) }
      self
    end

    private

    def visit(file)
      bytes = File.binread(File.join(@root, file))
      return if bytes.include?("\0")

      @manual.concat(ordinal_mentions(file, bytes))
      entry = @rewriter.call(file, bytes)
      @rewrites[file] = entry if entry
    end

    def ordinal_mentions(file, bytes)
      bytes.each_line.with_index(1).filter_map do |line, number|
        "#{file}:#{number} #{line[@ordinal]}" if line.match?(@ordinal)
      end
    end
  end

  # Which files are renamed to what.
  module Moves
    module_function

    # [[from, to], ...] and the files whose owning case cannot be told.
    def call(files, catalog)
      moves = []
      stranded = []
      files.each do |file|
        stem, rest = File.basename(file).split(".", 2)
        next unless catalog.base?(stem)

        pair = catalog.resolve_in(stem, File.dirname(file).split("/"))
        pair ? moves << [file, target(file, pair, rest)] : stranded << file
      end
      [moves, stranded]
    end

    def target(file, pair, rest)
      File.join(File.dirname(file), [pair.new_base, rest].compact.join("."))
    end

    private_class_method :target
  end

  # Renames that would overwrite something.
  module Conflicts
    module_function

    def call(root, moves)
      targets = moves.map(&:last)
      doubled(targets) + taken(root, targets)
    end

    def doubled(targets)
      targets.tally.select { |_, count| count > 1 }.map do |target, count|
        "#{target} is the target of #{count} files"
      end
    end

    def taken(root, targets)
      existing = targets.select { |t| File.exist?(File.join(root, t)) }
      existing.map { |target| "#{target} already exists" }
    end

    private_class_method :doubled, :taken
  end

  # What must hold once the migration has been applied.
  module Verification
    module_function

    def call(root)
      catalog = Catalog.new(Manifest.pairs(root))
      files = Tree.files(root)
      references(root, files, catalog) + names(files, catalog) +
        cases(root, catalog)
    end

    def references(root, files, catalog)
      files.flat_map do |file|
        bytes = File.binread(File.join(root, file))
        next [] if bytes.include?("\0")

        old_names(bytes, catalog).map do |name|
          "#{file}: old name #{name} still referenced"
        end
      end
    end

    def old_names(bytes, catalog)
      bytes.scan(TOKEN).uniq.select { |name| catalog.base?(name) }
    end

    def names(files, catalog)
      files.filter_map do |file|
        stem = File.basename(file).split(".", 2).first
        "#{file}: file still has an old name" if catalog.base?(stem)
      end
    end

    def cases(root, catalog)
      ids = catalog.pairs.map(&:new_id)
      absent = ids.flat_map { |id| absent_files(root, id) }
      absent + count_problems(root, ids)
    end

    def absent_files(root, id)
      REQUIRED_EXTENSIONS.filter_map do |ext|
        file = "#{CORPUS}/#{id}.#{ext}"
        "#{file}: missing" unless File.file?(File.join(root, file))
      end
    end

    def count_problems(root, ids)
      on_disk = Dir.glob("*/*.mmd", base: File.join(root, CORPUS))
        .map { |file| file.delete_suffix(".mmd") }
      return [] if on_disk.sort == ids.sort

      ["#{CORPUS} holds #{on_disk.length} cases, the manifest names " \
       "#{ids.length}; extra: #{(on_disk - ids).first(3)}"]
    end

    private_class_method :references, :old_names, :names, :cases,
                         :absent_files, :count_problems
  end

  # Writes a Plan: rewritten contents first, then the renames.
  module Writer
    module_function

    def call(root, plan)
      plan.rewrites.each { |file, entry| replace(root, file, entry[:text]) }
      plan.moves.each do |from, to|
        File.rename(File.join(root, from), File.join(root, to))
      end
    end

    def replace(root, file, text)
      full = File.join(root, file)
      mode = File.stat(full).mode & 0o7777
      Tempfile.create([File.basename(file), ".tmp"], File.dirname(full)) do |t|
        t.binmode
        t.write(text)
        t.close
        File.chmod(mode, t.path)
        File.rename(t.path, full)
      end
    end

    private_class_method :replace
  end

  # Text of a plan for people.
  module Report
    module_function

    def call(plan, summary:)
      lines = counts(plan)
      lines.concat(details(plan)) unless summary
      lines.join("\n")
    end

    def counts(plan)
      ["moves: #{plan.moves.length}",
       "files rewritten: #{plan.rewrites.length}",
       "references rewritten: #{plan.references}",
       "unresolved: #{plan.unresolved.length}",
       "conflicts: #{plan.conflicts.length}",
       "ordinal-only mentions for manual review: #{plan.manual.length}"]
    end

    def details(plan)
      moves = plan.moves.map { |from, to| "move #{from} -> #{to}" }
      moves + rewrites(plan) + flagged(plan)
    end

    def rewrites(plan)
      plan.rewrites.sort.map do |file, entry|
        "rewrite #{file}: #{entry[:count]} references (#{entry[:ordering]})"
      end
    end

    def flagged(plan)
      plan.unresolved.map { |item| "UNRESOLVED #{item}" } +
        plan.conflicts.map { |item| "CONFLICT #{item}" } +
        plan.manual.map { |item| "MANUAL #{item}" }
    end

    private_class_method :counts, :details, :rewrites, :flagged
  end

  # The command line. Only this module turns a result into an exit status.
  module Cli
    module_function

    USAGE = "usage: apply_case_migration.rb " \
            "--dry-run [--summary] | --apply | --verify [--root DIR]"
    MODES = { "--dry-run" => :dry_run, "--apply" => :apply,
              "--verify" => :verify }.freeze

    def call(argv, root:, out:, err:)
      options = parse(argv)
      return usage(err) unless options[:mode]

      dispatch(options, options.fetch(:root, root), out, err)
    rescue OptionParser::ParseError
      usage(err)
    rescue Error => e
      err.puts "#{e.class}: #{e.message}"
      1
    end

    def parse(argv)
      options = {}
      OptionParser.new do |parser|
        MODES.each { |flag, mode| parser.on(flag) { options[:mode] = mode } }
        parser.on("--summary") { options[:summary] = true }
        parser.on("--root DIR") { |dir| options[:root] = dir }
      end.parse!(argv.dup)
      options
    end

    def usage(err)
      err.puts USAGE
      2
    end

    def dispatch(options, root, out, err)
      case options[:mode]
      when :verify then verify(root, out, err)
      when :apply then apply(root, out, err)
      else dry_run(root, out, options[:summary])
      end
    end

    def dry_run(root, out, summary)
      plan = ApplyCaseMigration.plan(root: root)
      out.puts Report.call(plan, summary: summary)
      plan.blocked? ? 1 : 0
    end

    def apply(root, out, err)
      plan = ApplyCaseMigration.apply!(root: root)
      out.puts Report.call(plan, summary: true)
      verify(root, out, err)
    end

    def verify(root, out, err)
      problems = ApplyCaseMigration.verify(root: root)
      problems.each { |problem| err.puts problem }
      out.puts(problems.empty? ? "verify: ok" : "verify: #{problems.length}")
      problems.empty? ? 0 : 1
    end

    private_class_method :parse, :usage, :dispatch, :dry_run, :apply, :verify
  end

  module_function

  def plan(root:)
    root = File.expand_path(root)
    catalog = Catalog.new(Manifest.pairs(root))
    require_cases_on_disk(root, catalog)
    build_plan(root, catalog, Tree.files(root))
  end

  def build_plan(root, catalog, files)
    scan = Scan.new(root, catalog).run(files)
    moves, stranded = Moves.call(files, catalog)
    Plan.new(moves: moves, rewrites: scan.rewrites,
             unresolved: scan.unresolved + untyped(stranded),
             conflicts: Conflicts.call(root, moves), manual: scan.manual)
  end

  def apply!(root:)
    root = File.expand_path(root)
    raise DirtyTreeError, "working tree is not clean" unless Tree.clean?(root)

    plan = plan(root: root)
    refuse(plan)
    Writer.call(root, plan)
    plan
  end

  # The problems found; an empty list means the migration is complete.
  def verify(root:)
    Verification.call(File.expand_path(root))
  end

  def run(argv, root: Dir.pwd, out: $stdout, err: $stderr)
    Cli.call(argv, root: root, out: out, err: err)
  end

  def require_cases_on_disk(root, catalog)
    absent = catalog.pairs.reject do |pair|
      File.file?(File.join(root, CORPUS, pair.type, "#{pair.old_base}.mmd"))
    end
    return if absent.empty?

    raise ManifestError, "#{absent.length} manifest cases are not on disk " \
                         "(already applied?), first: #{absent.first.old_id}"
  end

  def untyped(files)
    files.map { |file| "#{file} (named by several types, no type directory)" }
  end

  def refuse(plan)
    unless plan.conflicts.empty?
      raise ConflictError, "#{plan.conflicts.length} conflicts, first: " \
                           "#{plan.conflicts.first}; nothing written"
    end
    return if plan.unresolved.empty?

    raise UnresolvedError,
          "#{plan.unresolved.length} unresolved references; nothing written"
  end

  private_class_method :build_plan, :require_cases_on_disk, :untyped, :refuse
end

exit(ApplyCaseMigration.run(ARGV)) if $PROGRAM_NAME == __FILE__
