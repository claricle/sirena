# frozen_string_literal: true

require "open3"

# Shell and git helpers for specs that build real repositories in a tmpdir.
module GitRepoHelpers
  # `sh` passes this to every git command; any git that WRITES outside `sh`
  # needs it too. Without it, commit, fetch and push start a detached
  # `git maintenance run` that holds `.git/objects/maintenance.lock` while the
  # example deletes its tmpdir, failing a random example with
  # `Errno::ENOENT: apply2files - <tmpdir>/.git/objects/maintenance.lock`.
  # `GIT_TRACE=1 git commit` shows the spawn, and nothing once this is set.
  NO_AUTO_MAINTENANCE = {
    "GIT_CONFIG_COUNT" => "1",
    "GIT_CONFIG_KEY_0" => "maintenance.auto",
    "GIT_CONFIG_VALUE_0" => "false"
  }.freeze

  def sh(dir, *cmd)
    out, err, st = Open3.capture3(NO_AUTO_MAINTENANCE, *cmd, chdir: dir)
    raise "#{cmd.join(' ')}: #{err}" unless st.success?

    out.strip
  end

  def commit(dir, name)
    File.write(File.join(dir, name), name)
    sh(dir, "git", "add", name)
    sh(dir, "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", name)
    sh(dir, "git", "rev-parse", "HEAD")
  end

  def in_repo?(dir, sha)
    system("git", "cat-file", "-e", "#{sha}^{commit}", chdir: dir, err: File::NULL)
  end
end
