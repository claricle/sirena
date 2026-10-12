# frozen_string_literal: true

require "spec_helper"
require "digest"
require "rexml/document"
require "sirena/notation/plantuml/sequence"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module ParticipantGlyphs
          KINDS = %w[
            actor boundary collections control database entity participant queue
          ].freeze
          SIGNATURES = {
            "actor" => [0, 1, 1, 0, 0],
            "boundary" => [0, 1, 1, 0, 0],
            "collections" => [2, 0, 0, 0, 0],
            "control" => [0, 1, 0, 0, 1],
            "database" => [0, 0, 2, 0, 0],
            "entity" => [0, 1, 0, 1, 0],
            "participant" => [1, 0, 0, 0, 0],
            "queue" => [0, 0, 2, 0, 0],
          }.freeze
          TAGS = {
            "actor" => %w[ellipse path text],
            "boundary" => %w[ellipse path text],
            "collections" => %w[rect rect text],
            "control" => %w[ellipse polygon text],
            "database" => %w[path path text],
            "entity" => %w[ellipse line text],
            "participant" => %w[rect text],
            "queue" => %w[path path text],
          }.freeze
          ORDINARY_SHA256 =
            "f370754cc4770ed5f84aa17e6d8846ca27fce5cf0980cc95556b11721f002bd0"
          FIELDS = {
            rectangles: %i[x y width height],
            ellipses: %i[cx cy rx ry],
            lines: %i[x1 y1 x2 y2],
          }.freeze

          def kinds
            KINDS
          end

          def signatures
            SIGNATURES
          end

          def tags
            TAGS
          end

          def ordinary_sha256
            ORDINARY_SHA256
          end

          def parsed(source)
            Sirena::Notation::PlantUML::Sequence.parse(source)
          end

          def scene(source)
            result = parsed(source)
            result.transform.new.call(result.diagram)
          end

          def render(source)
            result = parsed(source)
            laid_out = result.transform.new.call(result.diagram)
            result.renderer.new.render(laid_out).to_xml
          end

          def corpus_source
            path = File.expand_path(
              "../../../../plantuml/sequence/" \
              "resources.vega.nonreg.svg.SVG0001--7624adcaae49.puml",
              __dir__,
            )
            File.read(path)
          end

          def signature(head)
            %i[rectangles ellipses paths lines polygons].map do |collection|
              Array(head.public_send(collection)).size
            end
          end

          def participant_groups(document)
            xpath = "//g[starts-with(@id, 'participant-')]"
            REXML::XPath.match(document, xpath)
          end

          def primitive_values(head)
            coordinate_values(head) + Array(head.paths).map(&:data) +
              Array(head.polygons).map(&:points)
          end

          def coordinate_values(head)
            FIELDS.flat_map do |collection, fields|
              Array(head.public_send(collection)).flat_map do |item|
                fields.map { |field| item.public_send(field) }
              end
            end
          end
        end
      end
    end
  end
end

RSpec.describe Sirena::Notation::PlantUML::Sequence::ParticipantGlyphs do
  include described_class

  it "publishes the pinned SVG0001 primitive table in the Scene" do
    heads = scene(corpus_source).heads

    expect(heads.map { |head| [head.kind, signature(head)] })
      .to eq(kinds.map { |kind| [kind, signatures.fetch(kind)] } * 2)
  end

  it "serializes a distinct glyph at both ends of every lifeline" do
    groups = participant_groups(REXML::Document.new(render(corpus_source)))
    expected_tags = kinds.map { |kind| tags.fetch(kind) } * 2

    expect(groups.map { |group| group.elements.map(&:name) })
      .to eq(expected_tags)
  end

  it "labels the SVG0001 glyphs without synthetic kind-name text" do
    groups = participant_groups(REXML::Document.new(render(corpus_source)))

    expect(groups.map { |group| group.get_elements("text").map(&:text) })
      .to eq(kinds.map { |kind| ["my_#{kind}"] } * 2)
  end

  it "puts final actor geometry above its top label" do
    top = scene(corpus_source).heads.first

    expect(top.ellipses.first.cy).to be < top.texts.first.y
  end

  it "puts final actor geometry below its tail label" do
    tail = scene(corpus_source).heads[kinds.size]

    expect(tail.ellipses.first.cy).to be > tail.texts.first.y
  end

  it "keeps every typed glyph primitive fully specified" do
    values = scene(corpus_source).heads.flat_map do |head|
      primitive_values(head)
    end

    expect(values).not_to include(nil)
  end

  it "omits every tail glyph after hide footbox" do
    hidden = scene(corpus_source.sub("@startuml", "@startuml\nhide footbox"))
    observed = [hidden.heads.map(&:kind),
                hidden.heads.map { |head| signature(head) }]
    expected = [kinds, kinds.map { |kind| signatures.fetch(kind) }]

    expect(observed).to eq(expected)
  end

  it "keeps the ordinary participant rendering byte-identical" do
    source = "@startuml\nA -> B\n@enduml\n"

    expect(Digest::SHA256.hexdigest(render(source))).to eq(ordinary_sha256)
  end
end
