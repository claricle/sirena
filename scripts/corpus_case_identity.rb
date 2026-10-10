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
    identity = identity_string(titles, record.fetch(:occurrence, 0))
    stem = slug(titles.last || File.basename(path, ".*"))
    "#{type}/#{stem}-#{digest8(path, identity, source)}"
  end

  # Returns the records in order, each with :occurrence and :id filled in.
  # Raises CollisionError rather than letting two cases share an ID.
  def assign_ids(records)
    seen = Hash.new(0)
    identified = records.map do |record|
      key = twin_key(record)
      occurrence = record.fetch(:occurrence) { seen[key] }
      seen[key] += 1
      with_id(record.merge(occurrence: occurrence))
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
    ensure_unique_cases(old)
    new_ids = assign_ids(new_records).map { |record| record[:id] }
    matched, orphaned = old.partition { |r| new_ids.include?(r[:id]) }
    { pairs: pairs_for(matched),
      deletions: cases_of(orphaned),
      additions: additions_for(matched, new_ids) }
  end

  def normalize_path(path)
    path.to_s.tr("\\", "/").squeeze("/").sub(%r{\A(?:\./|/)+}, "")
  end

  def normalize_source(source)
    source.to_s.gsub(/\r\n?/, "\n").gsub(/[ \t]+$/, "")
      .sub(/\A\n+/, "").sub(/\n+\z/, "")
  end

  def slug(text)
    cleaned = text.to_s.downcase.gsub(/[^a-z0-9]+/, "_").sub(/\A_+/, "")
    cleaned = cleaned[0, MAX_SLUG_LENGTH].sub(/_+\z/, "")
    cleaned.empty? ? "case" : cleaned
  end

  def digest8(path, identity, source)
    joined = [path, identity, source].join("\0")
    Digest::SHA256.hexdigest(joined)[0, HASH_LENGTH]
  end

  def cases_of(records)
    records.map { |record| record.fetch(:case) }.sort
  end

  def additions_for(matched, new_ids)
    (new_ids - matched.map { |record| record[:id] }).sort
  end

  def with_id(record)
    record.merge(id: id_for(record))
  end

  def pairs_for(matched)
    matched.map { |r| { old: r.fetch(:case), new: r[:id] } }
      .sort_by { |pair| pair[:old] }
  end

  def validated_parts(record)
    path = normalize_path(record[:upstream_path])
    titles = clean_titles(record[:title])
    reject_nul(path, *titles)
    raise InvalidRecordError, "upstream_path is empty" if path.empty?

    [valid_type(record[:type]), path, titles, utf8_source(record[:source])]
  end

  def valid_type(type)
    return type.to_s if TYPE_PATTERN.match?(type.to_s)

    raise InvalidRecordError, "type #{type.inspect} is not [a-z0-9_]+"
  end

  def clean_titles(title)
    Array(title).map { |part| part.to_s.split.join(" ") }.reject(&:empty?)
  end

  def utf8_source(source)
    text = String(source).dup.force_encoding(Encoding::UTF_8)
    return normalize_source(text) if text.valid_encoding?

    raise InvalidRecordError, "source is not valid UTF-8"
  end

  def reject_nul(*fields)
    return unless fields.any? { |field| field.include?("\0") }

    raise InvalidRecordError, "NUL in an upstream path or title"
  end

  def identity_string(titles, occurrence)
    return "occurrence:#{occurrence}" if titles.empty?

    base = titles.join(TITLE_SEPARATOR)
    occurrence.zero? ? base : "#{base}##{occurrence}"
  end

  def twin_key(record)
    validated_parts(record)
  end

  def raise_on_collision(identified)
    identified.group_by { |record| record[:id] }.each do |id, claimants|
      next if claimants.one?

      paths = claimants.map { |claimant| claimant[:upstream_path] }
      raise CollisionError,
            "#{claimants.length} cases claim #{id}: #{paths.join(', ')}"
    end
  end

  def ensure_unique_cases(old)
    dupes = old.group_by { |r| r.fetch(:case) }.reject { |_, v| v.one? }.keys
    return if dupes.empty?

    raise InvalidRecordError, "old cases listed twice: #{dupes.join(', ')}"
  end

  private_class_method :validated_parts, :valid_type, :clean_titles,
                       :utf8_source, :reject_nul, :identity_string,
                       :twin_key, :raise_on_collision, :ensure_unique_cases,
                       :pairs_for, :with_id, :additions_for, :cases_of
end
