# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# A hermetic, network-free rubocop project under spec/fixtures/lint_debt/
# materialised into a fresh tmpdir per example. Every checked-in fixture
# file carries a `.fixture` suffix so the real repo's own lint lane
# never inspects it (`Gemfile`, `*.gemspec` and friends are otherwise
# matched by rubocop's default `Include` list regardless of directory).
module LintDebtFixture
  def fixtures_dir
    File.expand_path("../fixtures/lint_debt", __dir__)
  end

  def root
    @root ||= begin
      dir = File.realpath(Dir.mktmpdir)
      materialize_fixture!(dir)
      dir
    end
  end

  def materialize_fixture!(root)
    pattern = File.join(fixtures_dir, "*.fixture")
    Dir.glob(pattern, File::FNM_DOTMATCH).each do |path|
      next if File.basename(path).start_with?("..")

      FileUtils.cp(path, File.join(root, File.basename(path, ".fixture")))
    end
  end

  def write(relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
