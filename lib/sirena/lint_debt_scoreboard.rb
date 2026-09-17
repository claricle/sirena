# frozen_string_literal: true

require "yaml"
require "fileutils"

module Sirena
  # Persists a Sirena::LintDebt measurement into scoreboard/lint-debt/,
  # one file per cop, and compares a later measurement back against what
  # is checked in. This is the ratchet: `record!` refuses to write a
  # baseline that moves debt the wrong way, and `diff` is what `check`
  # reads to refuse a working tree that no longer matches what shipped.
  class LintDebtScoreboard
    # Raised by `record!` when the new baseline would increase a row's
    # count, or add a row absent from the checked-in baseline, without
    # the override env var set.
    class RefusedError < StandardError; end

    ALLOW_INCREASE_ENV = "SIRENA_LINT_DEBT_ALLOW_INCREASE"

    def initialize(root:, debt:)
      @root = root
      @debt = debt
    end

    # Where the baseline lives. Public so a caller (or a spec) can point
    # at the same place this class reads and writes, rather than
    # re-deriving the path in parallel.
    def directory
      File.join(root, "scoreboard", "lint-debt")
    end

    # Writes the current rows into the scoreboard, refusing to widen debt
    # unless overridden, then deletes any cop file whose rows dropped to
    # zero. Returns a summary for the caller to print.
    def record!
      was_bootstrap = bootstrap?
      current = index(debt.rows)

      refuse_increase!(read_rows, current) unless was_bootstrap || override?

      write_rows!(current)
      prune!(current)
      write_meta!(override: !was_bootstrap && override?)

      summary(bootstrap: was_bootstrap, current: current)
    end

    # A Diff between what is checked in and a fresh measurement.
    def diff
      Diff.new(baseline: read_rows, current: index(debt.rows))
    end

    private

    attr_reader :root, :debt

    def bootstrap?
      !Dir.exist?(directory)
    end

    def summary(bootstrap:, current:)
      {
        bootstrap: bootstrap,
        cops_written: current_cops(current).size,
        total: debt.total,
      }
    end

    def index(rows)
      rows.to_h { |row| [[row.cop, row.file], row.count] }
    end

    def current_cops(current)
      current.keys.map(&:first).uniq
    end

    def override?
      ENV[ALLOW_INCREASE_ENV] == "1"
    end

    def refuse_increase!(baseline, current)
      offenders = current.filter_map do |key, count|
        widened(baseline, key, count)
      end
      return if offenders.empty?

      raise RefusedError, refusal_message(offenders)
    end

    def widened(baseline, key, count)
      old = baseline[key]
      return unless old.nil? || count > old

      "#{key[0]} #{key[1]}: #{old.inspect} -> #{count}"
    end

    def refusal_message(offenders)
      "record refused, debt increased:\n#{offenders.join("\n")}\n" \
        "set #{ALLOW_INCREASE_ENV}=1 to override"
    end

    def cop_path(cop)
      File.join(directory, "#{cop.tr('/', '-')}.yml")
    end

    def meta_path
      File.join(directory, "_meta.yml")
    end

    def existing_cop_files
      Dir.glob(File.join(directory, "*.yml")).reject do |path|
        File.basename(path) == "_meta.yml"
      end
    end

    def read_rows
      existing_cop_files.each_with_object({}) do |path, rows|
        read_cop_file!(path, rows)
      end
    end

    def read_cop_file!(path, rows)
      data = YAML.safe_load_file(path)
      cop = data.fetch("cop")
      Array(data["rows"]).each do |row|
        rows[[cop, row.fetch("file")]] = row.fetch("count")
      end
    end

    def write_rows!(current)
      FileUtils.mkdir_p(directory)
      current.group_by { |(cop, _file), _count| cop }.each do |cop, entries|
        write_cop_file!(cop, entries)
      end
    end

    def write_cop_file!(cop, entries)
      rows = entries
        .map { |(_cop, file), count| { "file" => file, "count" => count } }
        .sort_by { |row| row["file"] }
      File.write(cop_path(cop), { "cop" => cop, "rows" => rows }.to_yaml)
    end

    def prune!(current)
      kept = current_cops(current)
      existing_cop_files.each { |path| prune_file!(path, kept) }
    end

    def prune_file!(path, kept_cops)
      data = YAML.safe_load_file(path)
      File.delete(path) unless kept_cops.include?(data["cop"])
    end

    def write_meta!(override:)
      meta = {
        "rubocop_version" => debt.rubocop_version,
        "recorded_with_override" => override,
      }
      File.write(meta_path, meta.to_yaml)
    end

    # The rows that differ between a baseline and a fresh measurement,
    # indexed by [cop, file] => count.
    class Diff
      # One difference between the checked-in baseline and a fresh
      # measurement: a row whose count moved.
      Change = Data.define(:cop, :file, :from, :to)

      def initialize(baseline:, current:)
        @baseline = baseline
        @current = current
      end

      def added
        @added ||= (current.keys - baseline.keys).sort
      end

      def removed
        @removed ||= (baseline.keys - current.keys).sort
      end

      def changed
        @changed ||= (baseline.keys & current.keys).sort.filter_map do |key|
          change_for(key)
        end
      end

      def clean?
        added.empty? && removed.empty? && changed.empty?
      end

      def to_s
        (added_lines + removed_lines + changed_lines).join("\n")
      end

      private

      attr_reader :baseline, :current

      def change_for(key)
        return if baseline[key] == current[key]

        Change.new(key[0], key[1], baseline[key], current[key])
      end

      def added_lines
        added.map { |cop, file| "+ #{cop} #{file}: #{current[[cop, file]]}" }
      end

      def removed_lines
        removed.map { |cop, file| "- #{cop} #{file}: #{baseline[[cop, file]]}" }
      end

      def changed_lines
        changed.map { |c| "~ #{c.cop} #{c.file}: #{c.from} -> #{c.to}" }
      end
    end
  end
end
