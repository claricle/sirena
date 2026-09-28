# frozen_string_literal: true

require "yaml"
require "open3"

# TODO.foundation/11-docs-truth-pass.md (Done when, lines 88-100): every row in
# docs/claims-manifest.yml disposed `removed` must have its exact claim string absent
# from tracked source, excluding docs/plans/, TODO.foundation/, _site/, and the
# manifest itself (those quote the very strings being removed as evidence).
#
#   ruby scripts/check_claims_manifest.rb
module Sirena
  module ClaimsManifestCheck
    # Distinct from ArgumentError (a malformed manifest) and SystemCallError
    # (a missing file): a bare `raise "string"` is unconditionally a
    # RuntimeError, which neither of those rescue clauses catches, so an
    # internal git-grep failure escaped as a raw backtrace instead of the
    # readable message every other failure path gives.
    class GitGrepError < StandardError; end

    MANIFEST_RELPATH = "docs/claims-manifest.yml"
    DISPOSITIONS = %w[verified corrected removed].freeze
    REQUIRED_KEYS = %w[claim file disposition evidence].freeze
    # docs/plans and TODO.foundation quote the very strings being removed as evidence
    # of what was wrong; _site is the built docs output; the manifest states them too;
    # this checker's own spec builds fixture claims that can read like real ones (a
    # future fixture string could collide with a real manifest claim, since the
    # pathspec below is otherwise bare "." -- every tracked file, including this
    # checker's own test file, counts as "evidence" unless named here explicitly).
    # Long-form `:(exclude)` magic, not the `:!` short form: git treats a `_` or `-`
    # immediately after `:!` as an unimplemented pathspec magic character and aborts
    # with "fatal: Unimplemented pathspec magic '_'" — reproduced against `_site`
    # with git 2.50.1 (Apple Git-155), so the short form cannot be used here.
    CLAIMS_MANIFEST_SPEC_RELPATH = "spec/scripts/check_claims_manifest_spec.rb"
    EXCLUDED_PATHSPECS = [":(exclude)docs/plans", ":(exclude)TODO.foundation", ":(exclude)_site",
                          ":(exclude)#{MANIFEST_RELPATH}",
                          ":(exclude)#{CLAIMS_MANIFEST_SPEC_RELPATH}"].freeze

    module_function

    def rows(manifest_path)
      loaded = YAML.safe_load_file(manifest_path)
      raise ArgumentError, "#{manifest_path}: expected a YAML list of rows" unless loaded.is_a?(Array)

      loaded.each_with_index { |row, index| validate_row!(row, index, manifest_path) }
      loaded
    end

    def validate_row!(row, index, manifest_path)
      raise ArgumentError, "#{manifest_path}: row #{index} is not a mapping" unless row.is_a?(Hash)

      missing = REQUIRED_KEYS - row.keys
      raise ArgumentError, "#{manifest_path}: row #{index} missing #{missing.join(', ')}" unless missing.empty?

      non_strings = REQUIRED_KEYS.reject { |key| row[key].is_a?(String) }
      unless non_strings.empty?
        raise ArgumentError,
              "#{manifest_path}: row #{index} #{non_strings.join(', ')} must be string, " \
              "got #{non_strings.map { |key| row[key].class }.join(', ')}"
      end
      unless DISPOSITIONS.include?(row["disposition"])
        raise ArgumentError,
              "#{manifest_path}: row #{index} has disposition #{row['disposition'].inspect}, " \
              "want one of #{DISPOSITIONS.join(', ')}"
      end

      # git grep -F -e treats an embedded newline as a line break between
      # separate OR'd patterns, not a literal character inside one pattern --
      # reproduced empirically: `git grep -F -e $'AAA\nZZZ'` matches a file
      # containing only "AAA" on its own line. A multi-line claim would
      # therefore be checked line-by-line-OR'd instead of as the single
      # string it names, silently weakening (or over-broadening) what
      # "still present"/"absent" means. Reject it at validation time instead.
      return unless row["claim"].include?("\n")

      raise ArgumentError, "#{manifest_path}: row #{index} claim must not contain a newline"
    end

    # Only `removed` rows are mechanically checkable; `corrected`/`verified` rows are
    # skipped here (their evidence field names a command a human/CI runs separately).
    def problems(root: ".")
      manifest_path = File.join(root, MANIFEST_RELPATH)
      rows(manifest_path).select { |row| row["disposition"] == "removed" }
        .filter_map { |row| removed_row_problem(row, root) }
    end

    def removed_row_problem(row, root)
      return unless present_in_tracked_source?(row.fetch("claim"), root)

      "claim marked removed still appears in tracked source: #{row['claim'].inspect} (was #{row['file']})"
    end

    # git grep (no --cached/--no-index) matches only tracked file content in `root`,
    # never an untracked file — verified empirically this session. -F: fixed string,
    # no regex surprises from `~`/`*`/`|` in a claim. -I: skip binary files. -q: only
    # the exit code matters. `git -C` inside a script is explicitly exempt from the
    # "never git -C" rule (~/.claude/CLAUDE.md hard-nevers: "scripts are exempt").
    def present_in_tracked_source?(claim, root)
      _out, err, status = Open3.capture3("git", "-C", root, "grep", "-F", "-I", "-q",
                                         "-e", claim, "--", ".", *EXCLUDED_PATHSPECS)
      case status.exitstatus
      when 0 then true
      when 1 then false
      else raise GitGrepError, "git grep failed: #{err.strip}"
      end
    end

    # Shared by the CLI entry point below and tasks/claims_manifest.rake, so
    # the pass/fail message contract lives in exactly one place. Returns a
    # boolean rather than exiting/aborting itself: this method is required
    # directly by spec/scripts/check_claims_manifest_spec.rb, so it is
    # library code, not an entry point -- `exit`/`abort` belong only where
    # `if __FILE__ == $PROGRAM_NAME` guards them, or in an actual rake task.
    def report!(root:)
      found = problems(root: root)
    rescue ArgumentError, SystemCallError, GitGrepError, Psych::Exception => e
      warn "claims manifest check failed: #{e.message}"
      false
    else
      if found.empty?
        puts "claims manifest: clean"
        true
      else
        warn(*found.map { |p| "claims manifest check failed: #{p}" })
        false
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(Sirena::ClaimsManifestCheck.report!(root: File.expand_path("..", __dir__)) ? 0 : 1)
end
