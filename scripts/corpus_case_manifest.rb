#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "tempfile"
require_relative "corpus_case_identity"
require_relative "../lib/sirena/corpus_type_names"

# Builds the old->new case-ID migration manifest from the committed corpus.
#
# Each spec/mermaid/<type>/NNN_<name>.meta.json records the upstream file
# (source_file), optionally the upstream test title (metadata.test_name) and
# sits beside its .mmd source, which is everything CorpusCaseIdentity needs.
# No mermaid-js checkout is involved. A case missing any of that is listed
# under "unmapped" with the reason; no ID is invented for it.
#
# The corpus has one directory per diagram type, so the type is the
# directory name.
#
#   ruby scripts/corpus_case_manifest.rb           # rewrite the manifest
#                                                  # (loses the old names)
#   ruby scripts/corpus_case_manifest.rb --check   # exit 1 if it is stale
module CorpusCaseManifest
  class Error < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  CORPUS_DIR = File.join(ROOT, "spec", "mermaid")
  MANIFEST_PATH = File.join(ROOT, "config", "corpus_case_migration.json")
  VERSION = 1
  # The checkout the extractor last ran against; older metas stored the
  # path with it still attached.
  CHECKOUT_PREFIX = %r{\A.*?/mermaid-js(?=/)}

  module_function

  def build(corpus_dir: CORPUS_DIR)
    records, unmapped = load_records(corpus_dir)
    manifest = CorpusCaseIdentity.migration_manifest(old_records: records,
                                                     new_records: records)
    { "version" => VERSION,
      "pairs" => manifest[:pairs].map { |p| p.transform_keys(&:to_s) },
      "unmapped" => unmapped.sort_by { |entry| entry["case"] } }
  end

  def render(manifest)
    "#{JSON.pretty_generate(manifest)}\n"
  end

  # Computes everything first; a CollisionError leaves the file untouched.
  def write(corpus_dir: CORPUS_DIR, path: MANIFEST_PATH)
    text = render(build(corpus_dir: corpus_dir))
    FileUtils.mkdir_p(File.dirname(path))
    Tempfile.create(["corpus_case_migration", ".json"],
                    File.dirname(path)) do |tmp|
      tmp.write(text)
      tmp.close
      File.rename(tmp.path, path)
    end
    text
  end

  # Compares the NEW side only. After the one-time rename the corpus files
  # carry the new ids, so the old names recorded in the manifest cannot be
  # rebuilt from the corpus and are kept as history.
  def stale?(corpus_dir: CORPUS_DIR, path: MANIFEST_PATH)
    return true unless File.file?(path)

    recorded = JSON.parse(File.read(path)).fetch("pairs").map { _1["new"] }
    current = build(corpus_dir: corpus_dir)["pairs"].map { _1["new"] }
    recorded.sort != current.sort
  end

  def load_records(corpus_dir)
    results = case_files(corpus_dir).map do |old_case|
      [old_case, *record_for(corpus_dir, old_case)]
    end
    found, missing = results.partition { |_, record, _| record }
    [found.map { |_, record, _| record },
     missing.map { |old_case, _, why| { "case" => old_case, "reason" => why } }]
  end

  def case_files(corpus_dir)
    from_mmd = Dir.glob("*/*.mmd", base: corpus_dir)
    metas = Dir.glob("*/*.meta.json", base: corpus_dir)
    from_meta = metas.map { |meta| meta.sub(/\.meta\.json\z/, ".mmd") }
    (from_mmd | from_meta).sort
  end

  def record_for(corpus_dir, old_case)
    meta_path = File.join(corpus_dir, old_case.sub(/\.mmd\z/, ".meta.json"))
    mmd_path = File.join(corpus_dir, old_case)
    return [nil, "no .meta.json"] unless File.file?(meta_path)
    return [nil, "no .mmd"] unless File.file?(mmd_path)

    build_record(old_case, JSON.parse(File.read(meta_path)), mmd_path)
  rescue JSON::ParserError
    [nil, "meta is not valid JSON"]
  end

  def build_record(old_case, meta, mmd_path)
    path = upstream_path(meta)
    return [nil, "meta has no source_file"] if path.nil?

    [{ case: old_case, type: old_case.split("/").first,
       upstream_path: path, title: (meta["metadata"] || {})["test_name"],
       source: File.binread(mmd_path) }, nil]
  end

  def upstream_path(meta)
    path = meta["source_file"]
    return nil unless path.is_a?(String) && !path.empty?

    path.sub(CHECKOUT_PREFIX, "")
  end

  private_class_method :load_records, :case_files, :record_for, :build_record,
                       :upstream_path
end

if $PROGRAM_NAME == __FILE__
  if ARGV.include?("--check")
    stale = CorpusCaseManifest.stale?
    warn "config/corpus_case_migration.json is stale" if stale
    exit(stale ? 1 : 0)
  end
  begin
    manifest = JSON.parse(CorpusCaseManifest.write)
    puts "pairs: #{manifest['pairs'].length}, " \
         "unmapped: #{manifest['unmapped'].length}"
  rescue CorpusCaseIdentity::Error => e
    warn "#{e.class}: #{e.message}"
    exit 1
  end
end
