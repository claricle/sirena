#!/usr/bin/env ruby
# frozen_string_literal: true

# Extracts PlantUML class and sequence diagram sources from PlantUML's own
# test resources into spec/plantuml/<type>/, one `.puml` + `.meta.json` per
# case, modeled on scripts/extract_mermaid_tests.rb.
#
#   ruby scripts/extract_plantuml_tests.rb --upstream /path/to/plantuml/checkout
#
# The checkout must be at the commit named in spec/plantuml/pin.json; the
# script refuses any other commit so the committed corpus stays reproducible.
# The selection rule and case-ID scheme are documented in
# spec/plantuml/README.md and implemented by PlantumlExtractor::Selection and
# PlantumlExtractor::CaseId.
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"

module PlantumlExtractor
  TYPES = %w[class sequence].freeze

  SOURCE_ROOTS = {
    resources: "src/test/resources",
    java: "src/test/java",
  }.freeze

  # Rules over the text of one @startuml..@enduml block. A block is classified
  # only on an explicit declaration, because PlantUML itself infers the type
  # and a bare `A -> B : hi` is valid in several diagram types.
  module Selection
    CLASS_MARKER = %r{
      ^\s*
      (?:abstract\s+class|abstract|class|interface|enum|annotation|protocol|
         struct|exception|metaclass|stereotype|circle|diamond)
      \s+["\w<]
    }x
    SEQUENCE_MARKER = %r{
      ^\s*(?:participant|actor|boundary|control|collections|queue)\s+["\w]
      |^\s*(?:activate|deactivate|autonumber|ref\s+over|return)\b
      |^\s*(?:alt|loop|opt|par|critical|break)\b.*$
      |^\s*==[^=].*==\s*$
      |^\s*newpage\b
    }x
    # Declarations that make the block belong to another diagram type or to
    # no UML type at all; any of these disqualifies it.
    OTHER_MARKER = %r{
      ^\s*(?:usecase|component|node|cloud|artifact|folder|frame|rectangle|
             state|start|stop|partition|mainframe|salt|gantt|mindmap|wbs|
             json|yaml|nwdiag|ditaa|ebnf|regex|chen|ER|map|object)\b
      |^\s*:.*;\s*$
      |^\s*@start(?!uml)
    }x
    # `entity` and `database` are not markers: use-case, deployment and
    # entity diagrams share them. `actor` is a marker only when no OTHER_MARKER
    # line is present.

    module_function

    # @return [String, nil] "class", "sequence", or nil when unclassified
    def type_of(source)
      return nil if source.match?(OTHER_MARKER)

      klass = source.match?(CLASS_MARKER)
      seq = source.match?(SEQUENCE_MARKER)
      return "class" if klass && !seq
      return "sequence" if seq && !klass

      nil
    end
  end

  # Case identity. Never an ordinal: inserting a fixture upstream must not
  # rename any other case.
  module CaseId
    module_function

    def normalize(source)
      source.gsub("\r\n", "\n").gsub(/[ \t]+$/, "").strip
    end

    def source_hash(source)
      Digest::SHA256.hexdigest(normalize(source))
    end

    # <upstream path sans extension, "/" as ".">[.<test identity>]--<12 hex
    # of source hash>. The test identity is appended only when it adds
    # something the path does not already say.
    def call(path:, test:, source:)
      stem = path.delete_prefix("src/test/").sub(%r{\.[^./]+\z}, "")
      base = stem.tr("/", ".")
      repeats = base.end_with?(".#{test}") || base == test
      slug = repeats ? base : "#{base}.#{test}"
      slug = slug.gsub(/[^A-Za-z0-9_.-]/, "_").gsub(/\.{2,}/, ".")
      "#{slug}--#{source_hash(source)[0, 12]}"
    end
  end

  Block = Struct.new(:path, :test, :origin, :source, :line, keyword_init: true)

  # Pulls @startuml..@enduml blocks out of upstream files.
  module Blocks
    BLOCK = /^[ \t]*@startuml\b[^\n]*\n.*?^[ \t]*@enduml\b[^\n]*$/m
    INDENT_BEFORE_MARKER = /^[ \t]+(?=@(?:start|end)uml)/

    module_function

    def from_resource(path, text, test:)
      scan(path, text, test: test, origin: "resource")
    end

    # Java tests keep diagrams inside a triple-quoted block (in a comment for
    # nonreg tests); the block text is taken verbatim, escapes unprocessed.
    def from_java(path, text, test:)
      text.scan(/"""(.*?)"""/m).flat_map do
        scan(path, Regexp.last_match(1), test: test, origin: "java-text-block")
      end
    end

    def scan(path, text, test:, origin:)
      text = text.gsub("\r\n", "\n")
      blocks = []
      text.scan(BLOCK) do
        match = Regexp.last_match
        line = text[0...match.begin(0)].count("\n") + 1
        blocks << Block.new(path: path, test: test, origin: origin,
                            source: match[0].gsub(INDENT_BEFORE_MARKER, ""),
                            line: line)
      end
      blocks
    end
  end

  # Walks a checkout and returns every block, unsorted.
  class Walker
    def initialize(root)
      @root = root
    end

    def blocks
      resource_blocks + java_blocks
    end

    private

    def resource_blocks
      files("#{SOURCE_ROOTS[:resources]}/**/*.puml").flat_map do |rel|
        Blocks.from_resource(rel, read(rel), test: File.basename(rel, ".puml"))
      end
    end

    def java_blocks
      files("#{SOURCE_ROOTS[:java]}/**/*.java").flat_map do |rel|
        Blocks.from_java(rel, read(rel), test: File.basename(rel, ".java"))
      end
    end

    def files(glob)
      Dir.glob(File.join(@root, glob))
        .map { |f| f.delete_prefix("#{@root}/") }.sort
    end

    def read(rel)
      File.read(File.join(@root, rel), encoding: "UTF-8").scrub
    end
  end

  # Turns blocks into {id => case} for the selected types.
  module Cases
    module_function

    def build(blocks)
      blocks.each_with_object({}) { |block, cases| add(cases, block) }
    end

    def add(cases, block)
      type = Selection.type_of(block.source)
      return unless TYPES.include?(type)

      id = CaseId.call(path: block.path, test: block.test, source: block.source)
      if cases.key?(id)
        cases[id][:meta][:occurrences] += 1
      else
        cases[id] = entry(block, id, type)
      end
    end

    def entry(block, id, type)
      source = "#{CaseId.normalize(block.source)}\n"
      { type: type, source: source, meta: meta(block, id, type) }
    end

    def meta(block, id, type)
      { id: id, type: type }.merge(
        where_from(block), what_it_is(block),
        provenance: "upstream-fixture", occurrences: 1
      )
    end

    def where_from(block)
      {
        upstream_path: block.path,
        test: block.test,
        origin: block.origin,
        line_number: block.line,
      }
    end

    def what_it_is(block)
      {
        source_sha256: CaseId.source_hash(block.source),
        uses_preprocessor: block.source.match?(/^\s*!/),
      }
    end
  end

  # Writes the corpus and fails loudly on a case-ID collision.
  module Writer
    module_function

    def write(cases, out_dir)
      cases.each do |id, kase|
        dir = File.join(out_dir, kase[:type])
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "#{id}.puml"), kase[:source])
        meta = "#{JSON.pretty_generate(kase[:meta])}\n"
        File.write(File.join(dir, "#{id}.meta.json"), meta)
      end
    end

    def clear(out_dir)
      TYPES.each do |type|
        Dir.glob(File.join(out_dir, type, "*.{puml,meta.json}"))
          .each { |f| File.delete(f) }
      end
    end
  end

  # Checksum over the committed corpus: one line per case, "type/id sha256".
  module Manifest
    module_function

    def lines(out_dir)
      TYPES.flat_map do |type|
        Dir.glob(File.join(out_dir, type, "*.meta.json")).map do |meta|
          data = JSON.parse(File.read(meta))
          "#{type}/#{data['id']} #{data['source_sha256']}"
        end
      end.sort
    end

    def digest(out_dir)
      Digest::SHA256.hexdigest("#{lines(out_dir).join("\n")}\n")
    end

    def counts(out_dir)
      TYPES.to_h do |type|
        [type, Dir.glob(File.join(out_dir, type, "*.puml")).size]
      end
    end
  end

  def self.head_sha(root)
    out, status = Open3.capture2("git", "rev-parse", "HEAD", chdir: root)
    raise "not a git checkout: #{root}" unless status.success?

    out.strip
  end

  def self.run(upstream:, out_dir:, pin_path:)
    pin = JSON.parse(File.read(pin_path))
    verify_pin!(pin, upstream)
    cases = Cases.build(Walker.new(upstream).blocks)
    Writer.clear(out_dir)
    Writer.write(cases, out_dir)
    update_pin(pin, pin_path, out_dir)
    Manifest.counts(out_dir)
  end

  def self.verify_pin!(pin, upstream)
    actual = head_sha(upstream)
    pinned = pin.dig("upstream", "sha")
    return if actual == pinned

    raise "upstream checkout is at #{actual}, pin.json says #{pinned}"
  end

  def self.update_pin(pin, pin_path, out_dir)
    pin["corpus"] = {
      "cases" => Manifest.counts(out_dir),
      "manifest_sha256" => Manifest.digest(out_dir),
    }
    File.write(pin_path, "#{JSON.pretty_generate(pin)}\n")
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("..", __dir__)
  opts = {
    out_dir: File.join(root, "spec/plantuml"),
    pin_path: File.join(root, "spec/plantuml/pin.json"),
  }
  OptionParser.new do |o|
    o.on("--upstream DIR") { |v| opts[:upstream] = v }
    o.on("--out DIR") { |v| opts[:out_dir] = v }
    o.on("--pin FILE") { |v| opts[:pin_path] = v }
  end.parse!
  abort "usage: extract_plantuml_tests.rb --upstream DIR" unless opts[:upstream]

  counts = PlantumlExtractor.run(**opts)
  puts counts.map { |t, n| "#{t}: #{n}" }.join("\n")
end
