# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"

module ChangelogScriptHelper
  # Runs scripts/check_changelog.rb as a subprocess against a throwaway
  # CHANGELOG.md and version.rb; returns Open3.capture3's [out, err, status].
  def run_script(*args, changelog:)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "CHANGELOG.md")
      File.write(path, changelog)
      version = File.join(dir, "version.rb")
      File.write(version, "VERSION = '0.1.9'\n")
      script = File.expand_path("../../scripts/check_changelog.rb", __dir__)
      Open3.capture3(RbConfig.ruby, script, args.first, path, version)
    end
  end
end
