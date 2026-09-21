# frozen_string_literal: true

require "open3"

# Shell and git helpers for specs that build real repositories in a tmpdir.
module GitRepoHelpers
  def sh(dir, *cmd)
    out, err, st = Open3.capture3(*cmd, chdir: dir)
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
