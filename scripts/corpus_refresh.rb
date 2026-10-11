# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

# Replaces a corpus directory with a freshly extracted one, or leaves it
# alone. The new tree is built in a sibling staging directory, checked
# against the old tree's case counts and provenance multiset, then moved
# into place. The .svg and .error sidecars are oracle output, not
# extraction output; they are never regenerated here, so a refresh drops
# them and the oracle recreates them.
module CorpusRefresh
  class Error < StandardError; end

  class LossyError < Error; end

  SHA_PATTERN = /\A\h{40}\z/

  module_function

  # Yields an empty staging directory. If the block finishes and the staged
  # tree matches the current one, the staged tree takes the target's place.
  # Otherwise the target is untouched and the staging directory is removed.
  def replace(target, accept_changes: false)
    stage = "#{target}.staging-#{Process.pid}"
    raise Error, "#{stage} already exists" if File.exist?(stage)

    FileUtils.mkdir_p(stage)
    yield stage
    verify!(target, stage) unless accept_changes
    swap(stage, target)
  ensure
    FileUtils.rm_rf(stage) if stage
  end

  # { [type, source_file, test_name, sha256 of the .mmd] => occurrences }
  def provenance(dir)
    Dir.glob("*/*.meta.json", base: dir).sort.each_with_object(
      Hash.new(0),
    ) do |meta_file, tally|
      tally[key_for(dir, meta_file)] += 1
    end
  end

  def verify!(target, stage)
    before = provenance(target)
    return if before.empty?

    after = provenance(stage)
    return if before == after

    raise LossyError, mismatch_message(before, after)
  end

  def key_for(dir, meta_file)
    meta = JSON.parse(File.read(File.join(dir, meta_file)))
    mmd = File.binread(File.join(dir, meta_file.sub(/\.meta\.json\z/, ".mmd")))
    [File.dirname(meta_file), meta["source_file"],
     (meta["metadata"] || {})["test_name"], Digest::SHA256.hexdigest(mmd)]
  end

  def mismatch_message(before, after)
    "refresh would change the corpus: #{before.values.sum} cases before, " \
      "#{after.values.sum} after; #{(before.to_a - after.to_a).length} " \
      "provenance entries differ from the old tree. Nothing was replaced."
  end

  # Not one atomic call: the old tree is renamed aside, the new one renamed
  # in, and the old one deleted. A failure between the renames puts the old
  # tree back. Top-level files (verdict tables, README) are carried across.
  def swap(stage, target)
    carry_over_files(target, stage)
    backup = "#{target}.old-#{Process.pid}"
    File.rename(target, backup) if File.exist?(target)
    install(stage, target, backup)
    FileUtils.rm_rf(backup)
  end

  def install(stage, target, backup)
    File.rename(stage, target)
  rescue SystemCallError
    File.rename(backup, target) if File.exist?(backup)
    raise
  end

  def carry_over_files(target, stage)
    return unless File.directory?(target)

    Dir.children(target).each do |name|
      source = File.join(target, name)
      FileUtils.cp(source, File.join(stage, name)) if File.file?(source)
    end
  end

  def validate_sha!(sha)
    return if sha.nil? || SHA_PATTERN.match?(sha)

    raise Error, "commit sha must be 40 hex characters: #{sha.inspect}"
  end

  private_class_method :verify!, :key_for, :mismatch_message, :swap,
                       :install, :carry_over_files
end
