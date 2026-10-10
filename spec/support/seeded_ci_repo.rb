# frozen_string_literal: true

require "open3"

# Builds the git shape a CI checkout has, inside a caller-owned temp dir.
#
#   main:     m1 -- m2 -- m3
#   release:  m1 -- r1
#   feature:        m2 -- f1 -- f2
#
# +origin+ holds every branch; +checkout+ clones it the way actions/checkout
# does, leaving the branches under refs/remotes/origin.
class SeededCiRepo
  IDENTITY = %w[-c user.name=t -c user.email=t@example.com].freeze

  attr_reader :origin, :shas

  def initialize(root)
    @root = root
    @origin = File.join(root, "origin")
    @shas = {}
    build_origin
  end

  # +depth+ makes a shallow checkout of +branch+ only, like fetch-depth: N.
  def checkout(name, branch:, depth: nil)
    dest = File.join(@root, name)
    args = ["clone", "--quiet", "--branch", branch]
    args += ["--depth", depth.to_s] if depth
    git(@root, *args, "file://#{origin}", dest)
    dest
  end

  def git(dir, *args)
    out, err, status = Open3.capture3("git", *IDENTITY, *args, chdir: dir)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out.strip
  end

  private

  def build_origin
    Dir.mkdir(origin)
    git(origin, "init", "--quiet", "--initial-branch=main")
    commit(:m1)
    branch_from(:release, :m1)
    commit(:r1)
    branch_from(:main, :m1)
    commit(:m2)
    branch_from(:feature, :m2)
    commit(:f1)
    commit(:f2)
    git(origin, "checkout", "--quiet", "main")
    commit(:m3)
  end

  def branch_from(branch, sha_key)
    git(origin, "checkout", "--quiet", "-B", branch.to_s, shas.fetch(sha_key))
  end

  def commit(key)
    git(origin, "commit", "--quiet", "--allow-empty", "-m", key.to_s)
    shas[key] = git(origin, "rev-parse", "HEAD")
  end
end
