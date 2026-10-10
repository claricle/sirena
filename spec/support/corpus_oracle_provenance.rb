# frozen_string_literal: true

require "digest"

# Provenance fixtures for spec/scripts/corpus_oracle_spec.rb.
module CorpusOracleProvenance
  # What every judged row must carry for the given rendered svg.
  def judged_provenance(svg)
    { "source_sha256" => match(/\A\h{64}\z/),
      "svg_sha256" => Digest::SHA256.hexdigest(svg),
      "toolchain" => { "mmdc" => CorpusOracle::EXPECTED_CLI } }
  end

  # The base provenance plus tools the row records but must not all keep.
  def full_provenance(base)
    base.merge("mermaid" => "11.16.1", "chromium" => "131.0", "node" => "22")
  end
end
