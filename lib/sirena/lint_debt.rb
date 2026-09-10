# frozen_string_literal: true

require "rubocop"
require "bundler"
require "date"
require "yaml"
require "json"
require "tmpdir"
require "open3"

module Sirena
  # Measures sirena's suppressed rubocop debt against a config this class
  # synthesises itself, rather than one loaded from `.rubocop.yml`. Every
  # local key in that file -- a fresh `Exclude`, a deleted plugin, a todo
  # file renamed and re-inherited under a new name -- is invisible to the
  # synthesis by construction, so no decision it makes can ever LOWER the
  # reported count, only raise it.
  #
  # The only thing this class reads from `.rubocop.yml` is its SHA-pinned
  # remote `inherit_from` entries. `plugins` comes from the pinned
  # `rubocop-*` gems in the Gemfile; `AllCops` is rebuilt from the
  # gemspec's Ruby floor and rubocop's own default `Include` list.
  class LintDebt
    # Raised when rubocop cannot be trusted to have run cleanly: a config
    # or usage error, or an ambient option source this class refuses to
    # run under.
    class ExecutionError < StandardError; end

    # The 13 cops card step 1 classifies as "metrics": the Metrics and
    # Naming departments, plus every cop carrying at least one
    # non-autocorrectable offence on this tree (measured in
    # TODO.foundation/09-cop-inventory.md). Fixed at that measurement
    # rather than recomputed per run -- the allowlist's category check
    # is a policy decision, not a live property of the current tree.
    METRICS_COPS = %w[
      Layout/LineLength
      Lint/DuplicateBranch
      Lint/DuplicateMethods
      Metrics/AbcSize
      Metrics/BlockLength
      Metrics/CyclomaticComplexity
      Metrics/MethodLength
      Metrics/ParameterLists
      Metrics/PerceivedComplexity
      Naming/MethodParameterName
      Naming/PredicateMethod
      Style/FormatStringToken
      Style/OneClassPerFile
    ].freeze

    # `09-rubocop-todo-burndown.md`'s only eligible exception location.
    GRAMMAR_PATH_PREFIX = "lib/sirena/parser/grammars/"

    OPTIONS_DOTFILE = ".rubocop"

    Row = Data.define(:cop, :file, :count)

    def initialize(root:)
      @root = File.realpath(root)
      refuse_ambient_options!
    end

    # Every (cop, file, count) row after the signed exception allowlist
    # is subtracted, sorted by cop then file so two runs on two machines
    # agree byte-for-byte.
    def rows
      @rows ||= apply_exceptions(measured_rows)
    end

    def total
      rows.sum(&:count)
    end

    def exceptions_applied
      exceptions.size
    end

    def rubocop_version
      RuboCop::Version::STRING
    end

    # The three suppression layers, nested rather than partitioned: a
    # doubly-suppressed offence is attributed to whichever layer's
    # removal makes it visible. The order is fixed: the todo file, then
    # `.rubocop.yml`'s own keys, then inline directives.
    def by_source
      @by_source ||= {
        "todo" => todo_layer_count,
        "config" => config_layer_count - todo_layer_count,
        "inline" => inline_layer_count - config_layer_count,
      }
    end

    def report
      {
        "rubocop_version" => rubocop_version,
        "total" => total,
        "by_source" => by_source,
        "exceptions_applied" => exceptions_applied,
        "rows" => rows.map { |row| row_to_h(row) },
      }
    end

    private

    attr_reader :root

    def row_to_h(row)
      { "cop" => row.cop, "file" => row.file, "count" => row.count }
    end

    def todo_layer_count
      @todo_layer_count ||= offense_count(config_without_local_inherit)
    end

    def config_layer_count
      @config_layer_count ||= offense_count(synthesized_config)
    end

    def inline_layer_count
      @inline_layer_count ||= offense_count(
        synthesized_config, ignore_disable_comments: true
      )
    end

    def refuse_ambient_options!
      return unless File.file?(File.join(root, OPTIONS_DOTFILE))

      raise ExecutionError,
            "#{OPTIONS_DOTFILE} would silently change rubocop's " \
            "arguments -- remove it before measuring debt"
    end

    def measured_rows
      rows_from(run_rubocop(synthesized_config, ignore_disable_comments: true))
    end

    def rows_from(result)
      counts = Hash.new(0)
      result.fetch("files").each { |file| tally_file!(counts, file) }
      counts.sort.map { |(cop, file), count| Row.new(cop, file, count) }
    end

    def tally_file!(counts, file)
      file.fetch("offenses").each do |offense|
        key = [offense.fetch("cop_name"), file.fetch("path")]
        counts[key] += 1
      end
    end

    def offense_count(config, ignore_disable_comments: false)
      run_rubocop(config, ignore_disable_comments: ignore_disable_comments)
        .dig("summary", "offense_count")
    end

    def run_rubocop(config, ignore_disable_comments:)
      Dir.mktmpdir do |dir|
        run_rubocop_in(
          dir, config, ignore_disable_comments: ignore_disable_comments
        )
      end
    end

    def run_rubocop_in(dir, config, ignore_disable_comments:)
      config_path = File.join(File.realpath(dir), "rubocop.yml")
      File.write(config_path, config.to_yaml)

      out, err, status = capture_rubocop(
        config_path, ignore_disable_comments: ignore_disable_comments
      )
      raise_unless_trustworthy!(status, err)
      JSON.parse(out)
    end

    def capture_rubocop(config_path, ignore_disable_comments:)
      args = rubocop_args(
        config_path, ignore_disable_comments: ignore_disable_comments
      )
      env = { "RUBOCOP_OPTS" => nil, "RUBOCOP_VERSION" => nil }
      Open3.capture3(env, *args, chdir: root)
    end

    def rubocop_args(config_path, ignore_disable_comments:)
      args = [
        "bundle", "exec", "rubocop",
        "--config", config_path,
        "--format", "json"
      ]
      args << "--ignore-disable-comments" if ignore_disable_comments
      args << "."
      args
    end

    def raise_unless_trustworthy!(status, err)
      return if [0, 1].include?(status.exitstatus)

      raise ExecutionError, "rubocop exited #{status.exitstatus}: #{err}"
    end

    def synthesized_config
      {
        "inherit_from" => remote_inherit_from,
        "plugins" => pinned_plugins,
        "AllCops" => synthesized_all_cops,
      }
    end

    def synthesized_all_cops
      {
        "TargetRubyVersion" => target_ruby_version,
        "NewCops" => "enable",
        "Include" => default_include,
        "Exclude" => ["vendor/**/*"],
      }
    end

    def default_include
      RuboCop::ConfigLoader.default_configuration["AllCops"]["Include"]
    end

    def config_without_local_inherit
      own_config.merge("inherit_from" => remote_inherit_from)
    end

    def own_config
      @own_config ||= YAML.load_file(File.join(root, ".rubocop.yml"))
    end

    def remote_inherit_from
      Array(own_config["inherit_from"]).select do |entry|
        entry.to_s.start_with?("http")
      end
    end

    # Reads declared gem names through Bundler's own DSL evaluator, not a
    # text pattern -- a regex only matches the spellings it was written
    # for, and `gem('rubocop-rspec', ...)` (no space before the opening
    # paren) is valid Ruby that `gem\s+['"]` never matches, silently
    # dropping that plugin and its whole cop family. Bundler is the same
    # interpreter that decides what this project actually depends on, so
    # there is no way to spell a real gem declaration that this misses.
    def pinned_plugins
      dsl = Bundler::Dsl.new
      dsl.eval_gemfile(File.join(root, "Gemfile"))
      dsl.dependencies.map(&:name).grep(/\Arubocop-/)
    rescue Bundler::GemfileError => e
      raise ExecutionError, "could not parse #{root}/Gemfile: #{e.message}"
    end

    def target_ruby_version
      gemspec_path = Dir.glob(File.join(root, "*.gemspec")).first
      raise ExecutionError, "no gemspec found under #{root}" unless gemspec_path

      version_from_gemspec(gemspec_path)
    end

    def version_from_gemspec(gemspec_path)
      pattern = /required_ruby_version\s*=\s*['"]>=\s*(\d+)\.(\d+)/
      match = File.read(gemspec_path).match(pattern)
      unless match
        raise ExecutionError, "#{gemspec_path} sets no minimum Ruby version"
      end

      "#{match[1]}.#{match[2]}".to_f
    end

    def exceptions
      @exceptions ||= load_exceptions
    end

    # `permitted_classes: [Date]` because an unquoted `approved_on:
    # 2026-09-10` is the conventional way to write that field and YAML
    # parses it as a Date, not a String. `safe_load_file` permits String
    # by default but NOT Date, so an unquoted entry refused to load the
    # whole file. Measured:
    #
    #   YAML.safe_load(%(a: "2026-09-10")) -> OK, String
    #   YAML.safe_load(%(a: 2026-09-10))   -> Psych::DisallowedClass
    #
    # Nothing here reads `approved_on` back; a Date is permitted only so a
    # human-natural entry does not blow up the loader.
    def load_exceptions
      path = File.join(root, "scoreboard", "lint-exceptions.yml")
      return [] unless File.exist?(path)

      data = YAML.safe_load_file(path, permitted_classes: [Date])
      Array((data || {})["exceptions"])
    end

    def apply_exceptions(current_rows)
      exceptions.each do |exception|
        validate_exception!(exception, current_rows)
      end
      current_rows.reject { |row| signed?(row) }
    end

    def signed?(row)
      exceptions.any? do |exception|
        exception["cop"] == row.cop && exception["file"] == row.file
      end
    end

    def validate_exception!(exception, current_rows)
      cop = exception.fetch("cop")
      file = exception.fetch("file")

      refuse_wrong_class!(cop, file)
      refuse_wrong_location!(cop, file)
      refuse_missing_file!(cop, file)
      refuse_stale_entry!(cop, file, current_rows)
    end

    def refuse_wrong_class!(cop, file)
      return if METRICS_COPS.include?(cop)

      raise ExecutionError,
            "exception #{cop}/#{file}: #{cop} is not in the metrics class"
    end

    def refuse_wrong_location!(cop, file)
      return if file.start_with?(GRAMMAR_PATH_PREFIX)

      raise ExecutionError,
            "exception #{cop}/#{file}: not under #{GRAMMAR_PATH_PREFIX}"
    end

    def refuse_missing_file!(cop, file)
      return if File.file?(File.join(root, file))

      raise ExecutionError, "exception #{cop}/#{file}: file does not exist"
    end

    def refuse_stale_entry!(cop, file, current_rows)
      return if current_rows.any? { |row| row.cop == cop && row.file == file }

      raise ExecutionError,
            "exception #{cop}/#{file}: matches no current offence row"
    end
  end
end
