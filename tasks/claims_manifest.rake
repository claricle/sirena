# frozen_string_literal: true

require_relative "../scripts/check_claims_manifest"

desc "Check docs/claims-manifest.yml against tracked source"
task "claims_manifest:check" do
  root = File.expand_path("..", __dir__)
  clean = Sirena::ClaimsManifestCheck.report!(root: root)
  abort "claims_manifest:check: FAILED" unless clean
end
