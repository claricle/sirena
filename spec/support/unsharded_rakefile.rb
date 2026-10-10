# frozen_string_literal: true

# Loads the Rakefile as an unsharded run sees it. The Rakefile drops the
# trailing check tasks from `default` when SIRENA_SPEC_SHARD names a shard
# other than the last, so a spec asserting on `default` must not inherit
# the shard of the CI job running it.
module UnshardedRakefile
  RAKEFILE = File.expand_path("../../Rakefile", __dir__)

  def load_unsharded_rakefile
    shard = ENV.delete("SIRENA_SPEC_SHARD")
    load RAKEFILE
  ensure
    ENV["SIRENA_SPEC_SHARD"] = shard if shard
  end
end
