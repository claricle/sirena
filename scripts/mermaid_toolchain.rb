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
  CI_PUPPETEER_CONFIG_PATH = File.join(
    ROOT, "config", "mermaid-puppeteer-ci.json"
  )
  CI_CANARY_ENV = "SIRENA_ORACLE_CI_CANARY_NO_SANDBOX"
  FONTCONFIG_PATH = File.join(ROOT, "config", "mermaid-fonts.conf")
  MMDC_NAME = Gem.win_platform? ? "mmdc.cmd" : "mmdc"
  MMDC_PATH = File.join(ROOT, "node_modules", ".bin", MMDC_NAME)
  PACKAGE_ROOT = File.join(ROOT, "node_modules")
  FONT_ROOT = File.join(PACKAGE_ROOT, "@fontsource", "noto-sans", "files")
  REVISION_PATH = File.join(
    PACKAGE_ROOT, "puppeteer-core", "lib", "cjs", "puppeteer", "revisions.js"
  )

  class DriftError < StandardError; end

  module_function

  def provenance
    YAML.safe_load_file(PROVENANCE_PATH)
  end

  def verify_toolchain
    observed = resolved_provenance
    drift = provenance_drift(flatten(provenance), flatten(observed))
    raise DriftError, drift_message(drift) unless drift.empty?

    observed
  end

  def command(*arguments)
    if test_binary
      return [test_binary, *arguments]
    end

    verify_once
    [
      MMDC_PATH, "--configFile", CONFIG_PATH,
      "--cssFile", CSS_PATH,
      *ci_canary_browser_arguments,
      *arguments,
    ]
  end

  def test_mode?
    !test_binary.nil?
  end

  def version_command
    return [test_binary, "--version"] if test_binary

    verify_once
    [MMDC_PATH, "--version"]
  end

  def environment
    { "FONTCONFIG_FILE" => FONTCONFIG_PATH }
  end

  def render_canary
    verify_toolchain
    require "tmpdir"
    require_relative "hardened_mmdc"

    Dir.mktmpdir("mermaid-oracle-canary") { |dir| render_canary_in(dir) }
  end

  def resolved_provenance
    {
      "node" => version_of("node", "--version").delete_prefix("v"),
      "npm" => version_of("npm", "--version"),
      "mmdc" => package_version("@mermaid-js/mermaid-cli"),
      "mermaid" => package_version("mermaid"),
      "puppeteer" => package_version("puppeteer"),
      "chromium" => chromium_revision,
      "font" => resolved_font_provenance,
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
      raise(DriftError, "cannot read Chromium revision")
  rescue Errno::ENOENT
    raise DriftError, "missing #{REVISION_PATH}; run npm ci"
  end

  def font_hashes
    provenance.fetch("font").fetch("files").keys.to_h do |name|
      path = File.join(FONT_ROOT, name)
      raise DriftError, "missing pinned font #{path}" unless File.file?(path)

      [name, Digest::SHA256.file(path).hexdigest]
    end
  end

  def version_of(program, argument)
    output, status = Open3.capture2e(program, argument)
    return output.strip if status.success?

    raise DriftError, "#{program} #{argument} failed: #{output.strip}"
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

  def ci_canary_browser_arguments
    return [] unless ENV.fetch(CI_CANARY_ENV, nil) == "1"

    ["--puppeteerConfigFile", CI_PUPPETEER_CONFIG_PATH]
  end

  def verify_once
    return if @checked

    verify_toolchain
    @checked = :verified
  end

  def provenance_drift(expected, observed)
    expected.filter_map do |key, value|
      next if observed[key] == value

      "#{key}: expected #{value.inspect}, got #{observed[key].inspect}"
    end
  end

  def drift_message(drift)
    "Mermaid oracle toolchain drift:\n  #{drift.join("\n  ")}"
  end

  def resolved_font_provenance
    package = "@fontsource/noto-sans"
    {
      "package" => package,
      "version" => package_version(package),
      "integrity" => lock_integrity(package),
      "family" => "Noto Sans",
      "files" => font_hashes,
    }
  end

  def render_canary_in(dir)
    input = File.join(dir, "canary.mmd")
    output = File.join(dir, "canary.svg")
    File.write(input, "flowchart LR\n  A --> B\n")
    status, diagnostic = HardenedMmdc.run_mmdc(input, output)
    verify_canary(status, output, diagnostic)
  end

  def verify_canary(status, output, diagnostic)
    svg = File.read(output) if File.file?(output)
    return svg if status&.success? && svg&.include?("<svg") &&
                  svg.include?("Noto Sans")

    raise DriftError, "Mermaid oracle canary failed: #{diagnostic}"
  end

  private_class_method :package_version, :lock_integrity,
                       :chromium_revision, :font_hashes, :version_of,
                       :flatten, :test_binary, :verify_once,
                       :ci_canary_browser_arguments,
                       :provenance_drift, :drift_message,
                       :resolved_font_provenance, :render_canary_in,
                       :verify_canary
end

if $PROGRAM_NAME == __FILE__
  if ARGV == ["--check"]
    MermaidToolchain.verify_toolchain
    puts "Mermaid oracle toolchain matches #{MermaidToolchain::PROVENANCE_PATH}"
  elsif ARGV == ["--canary"]
    MermaidToolchain.render_canary
    puts "Mermaid oracle canary rendered with the pinned toolchain"
  else
    abort "usage: ruby scripts/mermaid_toolchain.rb --check|--canary"
  end
end
