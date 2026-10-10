# frozen_string_literal: true

require "digest"

# Stable corpus case identity: an ID derived from where a Mermaid diagram
# came from, never from its position among the other cases.
#
#   <type>/<slug>-<hash8>
#
# - type  the canonical type directory ([a-z0-9_]+)
# - slug  a short filesystem-safe form of the upstream test title
# - hash8 first 8 hex chars of SHA-256 over the canonical upstream path, the
#         identity string and the normalized source, joined by NUL
#
# The identity string is the upstream test title when there is one, else
# "occurrence:<n>". <n> counts blocks with the same (path, title, source), in
# extraction order, so only exact twins depend on order; inserting, reordering
# or deleting any other upstream test leaves every other ID alone.
#
# A record is a Hash with :type, :upstream_path, :source, optionally :title (a
# String, or an Array of describe/it titles) and :occurrence.
module CorpusCaseIdentity
  class Error < StandardError; end

  class InvalidRecordError < Error; end

  class CollisionError < Error; end

  TYPE_PATTERN = /\A[a-z0-9_]+\z/
  MAX_SLUG_LENGTH = 48
  HASH_LENGTH = 8
  TITLE_SEPARATOR = " > "

  module_function

  def id_for(record)
    type, path, titles, source = validated_parts(record)
    occurrence = record.fetch(:occurrence, 0)
    identity = identity_string(titles, occurrence)
    "#{type}/#{slug(titles.last || File.basename(path, '.*'))}-" \
      "#{digest8(path, identity, source)}"
  end

  # Returns the records in order, each with :occurrence and :id filled in.
  # Raises CollisionError rather than letting two cases share an ID.
  def assign_ids(records)
    seen = Hash.new(0)
    identified = records.map do |record|
      occurrence = record.fetch(:occurrence) { seen[twin_key(record)] }
      seen[twin_key(record)] += 1
      with_occurrence = record.merge(occurrence: occurrence)
      with_occurrence.merge(id: id_for(with_occurrence))
    end
    raise_on_collision(identified)
    identified
  end

  # Pairs every old ordinal case with the new ID of the same upstream block.
  # Old cases with no counterpart are returned as :deletions so a vanished
  # case is a visible decision, never a silent drop.
  #
  # old_records also carry :case (the ordinal path being retired).
  def migration_manifest(old_records:, new_records:)
    old = assign_ids(old_records)
    new_ids = assign_ids(new_records).to_h { |record| [record[:id], record] }
    ensure_unique_cases(old)

    matched, orphaned = old.partition { |record| new_ids.key?(record[:id]) }
    {
      pairs: matched.map { |r| { old: r.fetch(:case), new: r[:id] } }
        .sort_by { |pair| pair[:old] },
      deletions: orphaned.map { |r| r.fetch(:case) }.sort,
      additions: (new_ids.keys - matched.map { |r| r[:id] }).sort,
    }
  end

  def normalize_path(path)
    path.to_s.tr("\\", "/").squeeze("/").sub(%r{\A(?:\./|/)+}, "")
  end

  def normalize_source(source)
    source.to_s.gsub(/\r\n?/, "\n").gsub(/[ \t]+$/, "")
      .sub(/\A\n+/, "").sub(/\n+\z/, "")
  end

  def slug(text)
    cleaned = text.to_s.downcase.gsub(/[^a-z0-9]+/, "_")
    cleaned = cleaned.sub(/\A_+/, "")[0, MAX_SLUG_LENGTH].sub(/_+\z/, "")
    cleaned.empty? ? "case" : cleaned
  end

  def digest8(path, identity, source)
    Digest::SHA256.hexdigest([path, identity, source].join("\0"))[0, HASH_LENGTH]
  end

  def validated_parts(record)
    type = record[:type].to_s
    unless TYPE_PATTERN.match?(type)
      raise InvalidRecordError, "type #{type.inspect} is not [a-z0-9_]+"
    end

    path = normalize_path(record[:upstream_path])
    raise InvalidRecordError, "upstream_path is empty" if path.empty?

    titles = Array(record[:title]).map { |t| t.to_s.split.join(" ") }
      .reject(&:empty?)
    [type, path, titles, utf8_source(record[:source])].tap do |parts|
      ensure_no_nul(path, *titles, label: parts[0])
    end
  end

  def utf8_source(source)
    text = String(source).dup.force_encoding(Encoding::UTF_8)
    raise InvalidRecordError, "source is not valid UTF-8" unless text.valid_encoding?

    normalize_source(text)
  end

  def ensure_no_nul(*fields, label:)
    return unless fields.any? { |field| field.include?("\0") }

    raise InvalidRecordError, "NUL in path or title of a #{label} record"
  end

  def identity_string(titles, occurrence)
    return "occurrence:#{occurrence}" if titles.empty?

    base = titles.join(TITLE_SEPARATOR)
    occurrence.zero? ? base : "#{base}##{occurrence}"
  end

  def twin_key(record)
    type, path, titles, source = validated_parts(record)
    [type, path, titles, source]
  end

  def raise_on_collision(identified)
    identified.group_by { |record| record[:id] }.each do |id, claimants|
      next if claimants.one?

      raise CollisionError,
            "#{claimants.length} cases claim #{id}: " \
            "#{claimants.map { |c| c[:upstream_path] }.join(', ')}"
    end
  end

  def ensure_unique_cases(old)
    dupes = old.group_by { |r| r.fetch(:case) }.reject { |_, v| v.one? }.keys
    return if dupes.empty?

    raise InvalidRecordError, "old cases listed twice: #{dupes.join(', ')}"
  end

  private_class_method :validated_parts, :utf8_source, :ensure_no_nul,
                       :identity_string, :twin_key, :raise_on_collision,
                       :ensure_unique_cases
end
