# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "yaml"

# The one entry point for invoking Mermaid's oracle. It refuses to run unless
# the installed dependency tree matches the committed provenance exactly.
# That turns a toolchain change into an explicit reviewed manifest update
# instead of silently changing corpus verdicts or reference SVGs.
module MermaidToolchain
  ROOT = File.expand_path("..", __dir__)
  PROVENANCE_PATH = File.join(ROOT, "config", "mermaid-oracle.yml")
  CONFIG_PATH = File.join(ROOT, "config", "mermaid-oracle.json")
  CSS_PATH = File.join(ROOT, "config", "mermaid-oracle.css")
  FONTCONFIG_PATH = File.join(ROOT, "config", "mermaid-fonts.conf")
  MMDC_PATH = File.join(ROOT, "node_modules", ".bin", Gem.win_platform? ? "mmdc.cmd" : "mmdc")
  PACKAGE_ROOT = File.join(ROOT, "node_modules")
  FONT_ROOT = File.join(PACKAGE_ROOT, "@fontsource", "noto-sans", "files")
  REVISION_PATH = File.join(PACKAGE_ROOT, "puppeteer-core", "lib", "cjs", "puppeteer", "revisions.js")

  class DriftError < StandardError; end

  module_function

  def provenance
    YAML.safe_load_file(PROVENANCE_PATH)
  end

  # Command entry point: success returns true; drift raises instead of
  # returning false. The bang communicates that failure aborts the operation.
  # rubocop:disable Naming/PredicateMethod
  def check!
    expected = provenance
    observed = resolved_provenance
    drift = flatten(expected).filter_map do |key, value|
      actual = flatten(observed)[key]
      "#{key}: expected #{value.inspect}, got #{actual.inspect}" unless actual == value
    end
    raise DriftError, "Mermaid oracle toolchain drift:\n  #{drift.join("\n  ")}" unless drift.empty?

    true
  end
  # rubocop:enable Naming/PredicateMethod

  def command(*arguments)
    if test_binary
      return [test_binary, *arguments]
    end

    check_once!
    [MMDC_PATH, "--configFile", CONFIG_PATH, "--cssFile", CSS_PATH, *arguments]
  end

  def test_mode?
    !test_binary.nil?
  end

  def version_command
    return [test_binary, "--version"] if test_binary

    check_once!
    [MMDC_PATH, "--version"]
  end

  def environment
    { "FONTCONFIG_FILE" => FONTCONFIG_PATH }
  end

  # Like check!, this is an imperative command whose failure raises.
  # rubocop:disable Naming/PredicateMethod
  def canary!
    check!
    require "tmpdir"
    require_relative "hardened_mmdc"

    Dir.mktmpdir("mermaid-oracle-canary") do |dir|
      input = File.join(dir, "canary.mmd")
      output = File.join(dir, "canary.svg")
      File.write(input, "flowchart LR\n  A --> B\n")
      status, diagnostic = HardenedMmdc.run_mmdc(input, output)
      svg = File.read(output) if File.file?(output)
      valid = status&.success? && svg&.include?("<svg") && svg.include?("Noto Sans")
      raise DriftError, "Mermaid oracle canary failed: #{diagnostic}" unless valid
    end
    true
  end
  # rubocop:enable Naming/PredicateMethod

  def resolved_provenance
    {
      "node" => version_of("node", "--version").delete_prefix("v"),
      "npm" => version_of("npm", "--version"),
      "mmdc" => package_version("@mermaid-js/mermaid-cli"),
      "mermaid" => package_version("mermaid"),
      "puppeteer" => package_version("puppeteer"),
      "chromium" => chromium_revision,
      "font" => {
        "package" => "@fontsource/noto-sans",
        "version" => package_version("@fontsource/noto-sans"),
        "integrity" => lock_integrity("@fontsource/noto-sans"),
        "family" => "Noto Sans",
        "files" => font_hashes,
      },
    }
  end

  def package_version(name)
    path = File.join(PACKAGE_ROOT, name, "package.json")
    raise DriftError, "missing #{path}; run npm ci" unless File.file?(path)

    JSON.parse(File.read(path)).fetch("version")
  end

  def lock_integrity(name)
    lock = JSON.parse(File.read(File.join(ROOT, "package-lock.json")))
    lock.fetch("packages").fetch("node_modules/#{name}").fetch("integrity")
  rescue Errno::ENOENT, KeyError, JSON::ParserError => e
    raise DriftError, "cannot read locked #{name} integrity: #{e.message}"
  end

  def chromium_revision
    source = File.read(REVISION_PATH)
    source[/["']chrome-headless-shell["']:\s*["']([^"']+)/, 1] ||
      raise(DriftError, "cannot read Chromium revision from #{REVISION_PATH}")
  rescue Errno::ENOENT
    raise DriftError, "missing #{REVISION_PATH}; run npm ci"
  end

  def font_hashes
    provenance.fetch("font").fetch("files").keys.to_h do |name|
      path = File.join(FONT_ROOT, name)
      raise DriftError, "missing pinned font #{path}; run npm ci" unless File.file?(path)

      [name, Digest::SHA256.file(path).hexdigest]
    end
  end

  def version_of(program, argument)
    output, status = Open3.capture2e(program, argument)
    raise DriftError, "#{program} #{argument} failed: #{output.strip}" unless status.success?

    output.strip
  rescue Errno::ENOENT
    raise DriftError, "#{program} is missing"
  end

  def flatten(value, prefix = nil)
    return { prefix => value } unless value.is_a?(Hash)

    value.each_with_object({}) do |(key, child), rows|
      path = [prefix, key].compact.join(".")
      rows.merge!(flatten(child, path))
    end
  end

  # Tests exercise timeout and crash handling with deliberately fake binaries.
  # Both variables are required so an ordinary environment cannot accidentally
  # replace the oracle selected by the repository lockfile.
  def test_binary
    return unless ENV["SIRENA_ALLOW_TEST_MMDC"] == "1"

    ENV.fetch("SIRENA_MMDC_TEST_BIN", nil)
  end

  def check_once!
    return if @checked

    check!
    @checked = true
  end

  private_class_method :package_version, :lock_integrity, :chromium_revision, :font_hashes,
                       :version_of, :flatten, :test_binary, :check_once!
end

if $PROGRAM_NAME == __FILE__
  if ARGV == ["--check"]
    MermaidToolchain.check!
    puts "Mermaid oracle toolchain matches #{MermaidToolchain::PROVENANCE_PATH}"
  elsif ARGV == ["--canary"]
    MermaidToolchain.canary!
    puts "Mermaid oracle canary rendered with the pinned toolchain"
  else
    abort "usage: ruby scripts/mermaid_toolchain.rb --check|--canary"
  end
end
