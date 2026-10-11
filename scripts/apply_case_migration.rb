#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
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
# or a bare name next to a separate type. Twelve old names occur in more than
# one type; those are resolved by the directory written just before the name
# and, if there is none, listed as unresolved. Apply refuses to start while
# anything is unresolved.
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

  # One old->new case: `type`, the old and new file stem.
  class Pair
    attr_reader :type, :old_base, :new_base

    def initialize(type:, old_base:, new_base:)
      @type = type
      @old_base = old_base
      @new_base = new_base
    end
  end

  # Finds the pair a name refers to. A name used by several types needs a
  # directory to choose between them.
  class Catalog
    attr_reader :pattern, :pairs

    def initialize(pairs)
      @pairs = pairs
      @by_base = pairs.group_by(&:old_base)
      @pattern = TOKEN
    end

    def base?(name)
      @by_base.key?(name)
    end

    def ambiguous
      @by_base.select { |_, group| group.length > 1 }.keys
    end

    def candidates(base)
      @by_base.fetch(base)
    end

    def resolve(base, type)
      candidates = @by_base.fetch(base)
      return candidates.first if candidates.one?

      candidates.find { |pair| pair.type == type }
    end

    def resolve_in(base, directories)
      return @by_base.fetch(base).first if @by_base.fetch(base).one?

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

  # What apply would do: [from, to] renames, rewritten file contents, and
  # the references it cannot resolve.
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
      return [rewritten, :plain] unless case_lines?(before) &&
                                        "#{before.join("\n")}\n" == original

      after = rewritten.split("\n")
      after = after.sort if before == before.sort
      ["#{after.join("\n")}\n", :structured]
    end

    def case_lines?(list)
      !list.empty? && list.all? { |line| CASE_PATH.match?(line) }
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
      keys = before.keys
      pairs.sort_by!(&:first) if sorted_keys?(keys)
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

    private_class_method :structured, :lines, :case_lines?, :parse, :dump,
                         :order_like, :order_hash, :order_array,
                         :sorted_keys?, :sort_key
  end

  module_function

  def plan(root:)
    root = File.expand_path(root)
    catalog = Catalog.new(load_pairs(root))
    files = scope(root)
    check_corpus(root, catalog)
    rewrites, unresolved, manual = scan(root, files, catalog)
    moves, stranded = moves_for(files, catalog)
    Plan.new(moves: moves, rewrites: rewrites,
             unresolved: unresolved + stranded,
             conflicts: conflicts_for(root, moves), manual: manual)
  end

  def apply!(root:)
    root = File.expand_path(root)
    raise DirtyTreeError, "working tree is not clean" unless clean?(root)

    plan = plan(root: root)
    refuse_blocked(plan)

    write_rewrites(root, plan)
    plan.moves.each { |from, to| File.rename(path(root, from), path(root, to)) }
    plan
  end

  # Returns the problems found; an empty list means the migration is complete.
  def verify(root:)
    root = File.expand_path(root)
    catalog = Catalog.new(load_pairs(root))
    files = scope(root)
    problems = leftover_references(root, files, catalog)
    problems += leftover_files(files, catalog)
    problems + missing_cases(root, catalog)
  end

  def clean?(root)
    out, status = Open3.capture2("git", "status", "--porcelain", chdir: root)
    raise Error, "git status failed in #{root}" unless status.success?

    out.empty?
  end

  def scope(root)
    out, status = Open3.capture2(
      "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
      chdir: root
    )
    raise Error, "git ls-files failed in #{root}" unless status.success?

    out.split("\0").uniq.reject { |file| file == MANIFEST }.select do |file|
      full = path(root, file)
      File.file?(full) && !File.symlink?(full)
    end
  end

  def path(root, relative)
    File.join(root, relative)
  end

  def load_pairs(root)
    manifest = JSON.parse(File.read(path(root, MANIFEST)))
    pairs = Array(manifest["pairs"]).map { |entry| pair_for(entry) }
    reject_duplicates(pairs)
    pairs
  rescue Errno::ENOENT, JSON::ParserError => e
    raise ManifestError, "cannot read #{MANIFEST}: #{e.message}"
  end

  def pair_for(entry)
    old = OLD_PATTERN.match(entry["old"].to_s)
    new = NEW_PATTERN.match(entry["new"].to_s)
    unless old && new && old[1] == new[1]
      raise ManifestError, "bad manifest entry #{entry.inspect}"
    end

    Pair.new(type: old[1], old_base: old[2], new_base: new[2])
  end

  def reject_duplicates(pairs)
    %i[new_base old_base].each do |field|
      clash = pairs.group_by { |pair| [pair.type, pair.public_send(field)] }
        .select { |_, group| group.length > 1 }.keys
      next if clash.empty?

      raise ConflictError, "manifest lists #{field.to_s.tr('_', ' ')} twice: " \
                           "#{clash.map { |key| key.join('/') }.join(', ')}"
    end
  end

  def check_corpus(root, catalog)
    absent = catalog.pairs.reject do |pair|
      File.file?(path(root, "#{CORPUS}/#{pair.type}/#{pair.old_base}.mmd"))
    end
    return if absent.empty?

    names = absent.first(5).map { |pair| "#{pair.type}/#{pair.old_base}" }
    raise ManifestError, "#{absent.length} manifest cases are not on disk " \
                         "(already applied?): #{names.join(', ')}"
  end

  # [rewrites, unresolved, manual]. Files holding NUL bytes are left alone.
  def scan(root, files, catalog)
    rewrites = {}
    unresolved = []
    manual = []
    manual_pattern = ordinal_pattern(catalog)
    twins = Twins.new(root)
    files.each do |file|
      bytes = File.binread(path(root, file))
      next if bytes.include?("\0")

      manual.concat(ordinal_mentions(file, bytes, manual_pattern))
      entry = rewrite(file, bytes, catalog, twins, unresolved)
      rewrites[file] = entry if entry
    end
    [rewrites, unresolved, manual]
  end

  def rewrite(file, bytes, catalog, twins, unresolved)
    count = 0
    context = nil
    text = bytes.gsub(catalog.pattern) do
      match = Regexp.last_match
      next match[0] unless catalog.base?(match[0])

      hint = hint_before(bytes, match.begin(0))
      pair = catalog.resolve(match[0], hint)
      context = pair if pair && hint
      pair ||= twins.pick(catalog.candidates(match[0]), context)
      if pair
        count += 1
        pair.new_base
      else
        unresolved << unresolved_at(file, bytes, match)
        match[0]
      end
    end
    return if count.zero?

    ordered, ordering = Ordering.call(file, bytes, text)
    { text: ordered, count: count, ordering: ordering }
  end

  def unresolved_at(file, bytes, match)
    line = bytes[0, match.begin(0)].count("\n") + 1
    "#{file}:#{line} #{match[0]} (used by several types, no directory given)"
  end

  def hint_before(bytes, position)
    window = bytes[[position - HINT_WINDOW, 0].max...position]
    window[HINT, 1]
  end

  # `type NNN` or `type/NNN...`: an ordinal without the rest of the name
  # cannot be rewritten mechanically, so it is listed for a person.
  def ordinal_pattern(catalog)
    types = catalog.pairs.map(&:type).uniq.sort_by { |type| -type.size }
    /(?<![\w-])(?:#{Regexp.union(types)})[ \/]\d{3}(?![\w-])/
  end

  def ordinal_mentions(file, bytes, pattern)
    bytes.each_line.with_index(1).filter_map do |line, number|
      "#{file}:#{number} #{line[pattern]}" if line.match?(pattern)
    end
  end

  # [[from, to], ...] for every file named after a case, plus the files
  # whose owning case cannot be told.
  def moves_for(files, catalog)
    moves = []
    stranded = []
    files.each do |file|
      stem, rest = File.basename(file).split(".", 2)
      next unless catalog.base?(stem)

      suffix = rest ? ".#{rest}" : ""
      pair = catalog.resolve_in(stem, File.dirname(file).split("/"))
      if pair
        moves << [file, File.join(File.dirname(file), "#{pair.new_base}#{suffix}")]
      else
        stranded << "#{file} (named by several types, no type directory)"
      end
    end
    [moves, stranded]
  end

  def refuse_blocked(plan)
    unless plan.conflicts.empty?
      raise ConflictError, "#{plan.conflicts.length} conflicts, first: " \
                           "#{plan.conflicts.first}; nothing written"
    end
    return if plan.unresolved.empty?

    raise UnresolvedError,
          "#{plan.unresolved.length} unresolved references; nothing written"
  end

  def conflicts_for(root, moves)
    targets = moves.map(&:last)
    twice = targets.group_by(&:itself).select { |_, group| group.length > 1 }
    taken = targets.select { |target| File.exist?(path(root, target)) }
    twice.map { |target, group| "#{target} is the target of #{group.length} files" } +
      taken.map { |target| "#{target} already exists" }
  end

  def write_rewrites(root, plan)
    plan.rewrites.each do |file, entry|
      full = path(root, file)
      mode = File.stat(full).mode
      Tempfile.create([File.basename(file), ".tmp"], File.dirname(full)) do |tmp|
        tmp.binmode
        tmp.write(entry[:text])
        tmp.close
        File.chmod(mode & 0o7777, tmp.path)
        File.rename(tmp.path, full)
      end
    end
  end

  def leftover_references(root, files, catalog)
    files.flat_map do |file|
      bytes = File.binread(path(root, file))
      next [] if bytes.include?("\0")

      bytes.scan(catalog.pattern).uniq.select { |name| catalog.base?(name) }.map do |name|
        "#{file}: old name #{name} still referenced"
      end
    end
  end

  def leftover_files(files, catalog)
    files.filter_map do |file|
      stem = File.basename(file).split(".", 2).first
      "#{file}: file still has an old name" if catalog.base?(stem)
    end
  end

  def missing_cases(root, catalog)
    expected = catalog.pairs.to_h { |pair| ["#{pair.type}/#{pair.new_base}", pair] }
    problems = expected.keys.flat_map do |id|
      REQUIRED_EXTENSIONS.filter_map do |ext|
        file = "#{CORPUS}/#{id}.#{ext}"
        "#{file}: missing" unless File.file?(path(root, file))
      end
    end
    problems + case_count_problems(root, expected.keys)
  end

  def case_count_problems(root, expected_ids)
    found = Dir.glob("*/*.mmd", base: path(root, CORPUS)).map do |file|
      file.delete_suffix(".mmd")
    end
    return [] if found.sort == expected_ids.sort

    ["#{CORPUS} holds #{found.length} cases, the manifest names " \
     "#{expected_ids.length}; extra: #{(found - expected_ids).first(3)}"]
  end

  def describe(plan, summary:)
    lines = ["moves: #{plan.moves.length}",
             "files rewritten: #{plan.rewrites.length}",
             "references rewritten: #{plan.references}",
             "unresolved: #{plan.unresolved.length}",
             "conflicts: #{plan.conflicts.length}",
             "ordinal-only mentions for manual review: #{plan.manual.length}"]
    lines.concat(plan_details(plan)) unless summary
    lines.join("\n")
  end

  def plan_details(plan)
    moves = plan.moves.map { |from, to| "move #{from} -> #{to}" }
    rewrites = plan.rewrites.sort.map do |file, entry|
      "rewrite #{file}: #{entry[:count]} references (#{entry[:ordering]})"
    end
    moves + rewrites + plan.unresolved.map { |item| "UNRESOLVED #{item}" } +
      plan.conflicts.map { |item| "CONFLICT #{item}" } +
      plan.manual.map { |item| "MANUAL #{item}" }
  end

  def run(argv, root: Dir.pwd, out: $stdout, err: $stderr)
    options = parse_options(argv)
    return usage(err) unless options

    root = options[:root] || root
    dispatch(options, root, out, err)
  rescue Error => e
    err.puts "#{e.class}: #{e.message}"
    1
  end

  def parse_options(argv)
    options = {}
    OptionParser.new do |parser|
      parser.on("--dry-run") { options[:mode] = :dry_run }
      parser.on("--apply") { options[:mode] = :apply }
      parser.on("--verify") { options[:mode] = :verify }
      parser.on("--summary") { options[:summary] = true }
      parser.on("--root DIR") { |dir| options[:root] = dir }
    end.parse!(argv.dup)
    options[:mode] ? options : nil
  rescue OptionParser::ParseError
    nil
  end

  def usage(err)
    err.puts "usage: apply_case_migration.rb " \
             "--dry-run [--summary] | --apply | --verify [--root DIR]"
    2
  end

  def dispatch(options, root, out, err)
    case options[:mode]
    when :verify then report_verify(root, out, err)
    when :apply then report_apply(root, out, err)
    else report_plan(root, out, options[:summary])
    end
  end

  def report_plan(root, out, summary)
    plan = plan(root: root)
    out.puts describe(plan, summary: summary)
    plan.blocked? ? 1 : 0
  end

  def report_apply(root, out, err)
    plan = apply!(root: root)
    out.puts describe(plan, summary: true)
    problems = verify(root: root)
    problems.each { |problem| err.puts problem }
    problems.empty? ? 0 : 1
  end

  def report_verify(root, out, err)
    problems = verify(root: root)
    problems.each { |problem| err.puts problem }
    out.puts(problems.empty? ? "verify: ok" : "verify: #{problems.length} problems")
    problems.empty? ? 0 : 1
  end

  private_class_method :path, :load_pairs, :pair_for, :reject_duplicates,
                       :check_corpus, :refuse_blocked, :conflicts_for, :scan,
                       :rewrite, :unresolved_at, :hint_before,
                       :ordinal_pattern, :ordinal_mentions, :moves_for,
                       :write_rewrites,
                       :leftover_references, :leftover_files, :missing_cases,
                       :case_count_problems, :plan_details, :parse_options,
                       :usage, :dispatch, :report_plan, :report_apply,
                       :report_verify
end

exit(ApplyCaseMigration.run(ARGV)) if $PROGRAM_NAME == __FILE__
