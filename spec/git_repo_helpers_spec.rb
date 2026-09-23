# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "securerandom"
require "tmpdir"

# The specs that build throwaway repositories delete them with Dir.mktmpdir or
# FileUtils.remove_entry as soon as the example ends. Anything git leaves
# running past that point walks into the delete, so what is asserted here is
# that git leaves nothing running -- not that a particular file is absent,
# which a race can only ever report by luck.
RSpec.describe GitRepoHelpers do
  include described_class

  # Written for a real CI failure: `unit (ruby 3.3, macos-latest)` went red on
  # an unrelated example with
  # `Errno::ENOENT: apply2files - <tmpdir>/.git/objects/maintenance.lock`,
  # four times over two days, on main as well as on the branch, and passed on a
  # re-run of the same sha.
  describe "the git environment it runs commands in" do
    # Never read the machine's own git config. The counterexample below asserts
    # that git DOES spawn maintenance when left alone, and anyone who applied
    # the usual folk remedy for this flake -- `git config --global
    # maintenance.auto false` -- would otherwise make it fail on a correct tree.
    def isolated_config
      { "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_SYSTEM" => File::NULL }
    end

    # The counterexample deliberately leaves the detached maintenance child
    # running, so this is the one place in the suite that must survive the very
    # race the rest of the branch suppresses. Retrying the delete is correct
    # here and nowhere else: here a concurrent writer is known to exist because
    # the example asked for one.
    def in_throwaway_repo
      dir = Dir.mktmpdir("git-repo-helpers-spec")
      yield dir
    ensure
      10.times do
        FileUtils.remove_entry(dir)
        break
      rescue Errno::ENOENT
        # remove_entry raises this both for a file the child deleted mid-walk
        # (retry) and for a root that is already gone (done). Measured on ruby
        # 3.4.8: the second case raises too, so without this the loop would
        # spin out its whole budget after a successful delete.
        break unless File.exist?(dir)

        sleep 0.05
      end
      # `$!` is the exception already on its way out of the block, if any.
      # Raising over it would replace a real example failure with a cleanup
      # error, and the failure is the more useful of the two.
      raise "#{dir} survived 10 delete attempts: the maintenance child outlived them" if File.exist?(dir) && $!.nil?
    end

    # Commits in a repo of its own so neither example can see the other's, and
    # returns what git traced while doing it. The suppressed arm goes through
    # GitRepoHelpers#sh -- the real call site -- rather than through a second
    # copy of its Open3 call, so emptying the constant breaks this example.
    # The trace goes to a file because `sh` owns the command's stderr.
    def commit_trace(suppressed:)
      trace = File.join(Dir.tmpdir, "git-trace-#{SecureRandom.hex(8)}.log")
      env = isolated_config.merge("GIT_TRACE" => trace)
      args = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"]
      in_throwaway_repo do |dir|
        with_env(env) do
          sh(dir, "git", "init", "-q", "-b", "main")
          suppressed ? sh(dir, *args) : Open3.capture3(env, *args, chdir: dir)
        end
      end
      File.read(trace).tap { File.delete(trace) }
    end

    def with_env(env)
      restore = env.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
      ENV.update(env)
      yield
    ensure
      restore.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it "does not let a commit through #sh spawn the detached maintenance run" do
      expect(commit_trace(suppressed: true)).not_to include("maintenance run")
    end

    # The counterexample. Without it the example above passes on any git that
    # never had auto-maintenance, and would keep passing if the constant were
    # emptied, so it is what makes the assertion above mean anything.
    it "is a real suppression: git does spawn it when left to itself" do
      expect(commit_trace(suppressed: false)).to include("maintenance run")
    end
  end
end
