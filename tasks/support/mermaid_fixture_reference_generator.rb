# frozen_string_literal: true

# Generates only missing reference SVGs for the current parity blockers.
class MermaidReferenceGenerator
  class ConflictError < StandardError; end
  class GenerationError < StandardError; end

  TARGETS = {
    class_diagram: "class_diagram",
    er_diagram: "er_diagram",
    flowchart: "flowchart",
    gantt: "gantt",
    git_graph: "gitgraph",
    sequence: "sequence",
    state_diagram: "state_diagram",
  }.freeze
  CASE_PATH = %r{\A[a-z0-9_]+/[A-Za-z0-9_.-]+\.mmd\z}
  UNKNOWN_UPSTREAM = "unknown: corpus metadata has no upstream commit SHA"
  Reference = Data.define(
    :cases,
    :source_path,
    :reference_path,
    :source_sha256,
    :metadata,
  )

  def initialize(root: File.expand_path("../..", __dir__),
                 toolchain: MermaidToolchain,
                 runner: HardenedMmdc,
                 detector: nil,
                 canary: nil)
    @root = root
    @toolchain = toolchain
    @runner = runner
    @detector = detector || method(:detect_type)
    @canary = canary || -> { toolchain.render_canary }
  end

  def generate
    references = missing_references
    return verify_provenance! && [] if references.empty?

    generate_missing(references)
  end

  def generate_missing(references)
    toolchain_provenance = toolchain.verify_toolchain
    canary.call
    generated = []
    records = generate_records(references, generated)
    write_provenance(records, toolchain_provenance)
    references
  rescue StandardError
    generated&.each { |path| FileUtils.rm_f(path) }
    raise
  end

  def generate_records(references, generated)
    references.map do |reference|
      generate_reference(reference).tap do
        generated << reference.reference_path
      end
    end
  end

  def verify_provenance!
    records = read_provenance.fetch("references")
    records.each { |record| verify_record!(record) }
    records.length
  rescue Errno::ENOENT, KeyError, JSON::ParserError => e
    raise GenerationError, "invalid reference provenance: #{e.message}"
  end

  def missing_references
    cases = target_cases
    index = existing_reference_index(cases)
    grouped = cases.select { |entry| unresolved_reference?(entry, index) }
      .group_by { |entry| entry[:reference_path] }
    reject_conflicts!(grouped)
    grouped.map { |_path, entries| build_reference(entries) }
      .sort_by(&:reference_path)
  end

  private

  attr_reader :root, :toolchain, :runner, :detector, :canary

  def target_cases
    corpus_rows.filter_map do |row|
      next unless row["verdict"] == "valid" && row["pass"] == true

      target_case(row.fetch("case"))
    end
  end

  def target_case(case_id)
    validate_case_id!(case_id)
    source_path = File.join(root, "spec", "mermaid", case_id)
    source = File.binread(source_path)
    type = detector.call(source).to_sym
    directory = TARGETS[type]
    return unless directory

    reference_attributes(case_id, source_path, source, directory)
  end

  def reference_attributes(case_id, source_path, source, directory)
    {
      case_id: case_id,
      source_path: source_path,
      source_sha256: Digest::SHA256.hexdigest(source),
      reference_path: File.join(
        reference_root, directory, "#{File.basename(case_id, '.mmd')}.svg"
      ),
      metadata: source_metadata(source_path),
    }
  end

  def validate_case_id!(case_id)
    return if case_id.match?(CASE_PATH)

    raise GenerationError, "invalid corpus case path: #{case_id.inspect}"
  end

  def corpus_rows
    JSON.parse(File.read(File.join(root, "scoreboard", "corpus.json")))
  end

  def source_metadata(source_path)
    path = source_path.sub(/\.mmd\z/, ".meta.json")
    JSON.parse(File.read(path))
  rescue Errno::ENOENT
    {}
  end

  def detect_type(source)
    require "sirena"
    body = Sirena::Source.split(source).fetch(:body)
    Sirena::Notation::Mermaid.detect_type(body)
  end

  def reject_conflicts!(grouped)
    conflict = grouped.find do |_path, entries|
      entries.map { |entry| entry[:source_sha256] }.uniq.length > 1
    end
    return unless conflict

    path, entries = conflict
    cases = entries.map { |entry| entry[:case_id] }.join(", ")
    message = "conflicting sources target #{relative(path)}: #{cases}"
    raise ConflictError, message
  end

  def existing_reference_index(cases)
    cases.select { |entry| File.file?(entry[:reference_path]) }
      .group_by { |entry| entry[:source_sha256] }
  end

  def unresolved_reference?(entry, index)
    return false if File.file?(entry[:reference_path])

    exact_twins(entry, index).map do |candidate|
      File.binread(candidate[:reference_path])
    end.uniq.length != 1
  end

  def exact_twins(entry, index)
    index.fetch(entry[:source_sha256], []).select do |candidate|
      candidate_source = File.binread(candidate[:source_path])
      candidate_source == File.binread(entry[:source_path])
    end
  end

  def build_reference(entries)
    first = entries.first
    Reference.new(
      cases: entries.map { |entry| entry[:case_id] }.sort,
      source_path: first[:source_path],
      reference_path: first[:reference_path],
      source_sha256: first[:source_sha256],
      metadata: first[:metadata],
    )
  end

  def generate_reference(reference)
    FileUtils.mkdir_p(File.dirname(reference.reference_path))
    arguments = render_arguments(reference)
    status, diagnostic = runner.run_mmdc(
      reference.source_path,
      reference.reference_path,
    )
    validate_render!(reference.reference_path, status, diagnostic)
    provenance_record(reference, arguments)
  end

  def render_arguments(reference)
    ["-i", reference.source_path, "-o", reference.reference_path]
  end

  def validate_render!(path, status, diagnostic)
    document = REXML::Document.new(File.read(path)) if File.file?(path)
    return if valid_render?(document, status)

    message = "pinned mmdc failed for #{relative(path)}: #{diagnostic}"
    raise GenerationError, message
  rescue REXML::ParseException => e
    raise GenerationError, "pinned mmdc wrote invalid SVG for " \
                           "#{relative(path)}: #{e.message}"
  end

  def valid_render?(document, status)
    root_element = document&.root
    status&.success? && root_element&.name == "svg" &&
      root_element.attributes["aria-roledescription"] != "error"
  end

  def provenance_record(reference, arguments)
    metadata = reference.metadata
    reference_provenance(reference)
      .merge(upstream_provenance(metadata))
      .merge(source_provenance(metadata))
      .merge(generation_provenance(reference, arguments))
  end

  def reference_provenance(reference)
    {
      "reference" => relative(reference.reference_path),
      "cases" => reference.cases,
      "source_sha256" => reference.source_sha256,
    }
  end

  def source_provenance(metadata)
    {
      "upstream_source_file" => metadata["source_file"],
      "upstream_line_number" => metadata["line_number"],
    }
  end

  def generation_provenance(reference, arguments)
    {
      "generated_on" => Date.today.iso8601,
      "command" => reproducible_command(arguments),
      "output_sha256" => Digest::SHA256.file(reference.reference_path).hexdigest,
    }
  end

  def upstream_provenance(metadata)
    status = metadata["upstream_sha"] ? "recorded" : UNKNOWN_UPSTREAM
    {
      "upstream_sha" => metadata["upstream_sha"],
      "upstream_sha_status" => status,
    }
  end

  def reproducible_command(arguments)
    toolchain.command(*arguments).map { |argument| relative(argument) }
  end

  def write_provenance(new_records, toolchain_provenance)
    current = provenance_file? ? read_provenance.fetch("references") : []
    merged = (current + new_records).sort_by do |record|
      record.fetch("reference")
    end
    payload = {
      "schema" => 1,
      "toolchain" => toolchain_provenance,
      "references" => merged,
    }
    atomic_write(provenance_path, "#{JSON.pretty_generate(payload)}\n")
  end

  def atomic_write(path, contents)
    temporary = "#{path}.tmp-#{Process.pid}"
    File.write(temporary, contents)
    File.rename(temporary, path)
  ensure
    FileUtils.rm_f(temporary) if temporary
  end

  def verify_record!(record)
    reference = File.join(root, record.fetch("reference"))
    source = File.join(root, "spec", "mermaid", record.fetch("cases").first)
    verify_hash!(reference, record.fetch("output_sha256"), "output")
    verify_hash!(source, record.fetch("source_sha256"), "source")
    verify_command!(reference, record.fetch("command"))
  end

  def verify_command!(reference, command)
    return unless command.empty?

    raise GenerationError, "missing exact command for #{relative(reference)}"
  end

  def verify_hash!(path, expected, label)
    actual = Digest::SHA256.file(path).hexdigest
    return if actual == expected

    raise GenerationError, "#{label} checksum mismatch for #{relative(path)}"
  rescue Errno::ENOENT
    raise GenerationError, "missing #{label} file #{relative(path)}"
  end

  def provenance_file?
    File.file?(provenance_path)
  end

  def read_provenance
    JSON.parse(File.read(provenance_path))
  end

  def provenance_path
    File.join(reference_root, "reference-provenance.json")
  end

  def reference_root
    File.join(root, "spec", "fixtures_mermaid")
  end

  def relative(path)
    value = path.to_s
    prefix = "#{root}/"
    value.start_with?(prefix) ? value.delete_prefix(prefix) : value
  end
end
