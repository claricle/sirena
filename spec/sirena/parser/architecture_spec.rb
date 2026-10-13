# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/architecture"

RSpec.describe Sirena::Parser::Architecture, :aggregate_failures do
  let(:parser) { described_class.new }

  context "with simple architecture diagram" do
    let(:input) do
      <<~MERMAID
        architecture-beta
                    service db(database)[Database]
                    service server(server)[Server]

                    db:L -- R:server
      MERMAID
    end

    context "when parsing successfully" do
      let(:result) { parser.parse(input) }

      it "retains result" do
        expect(result).to be_a(Sirena::Diagram::Architecture)
      end

      it "retains result.services.size" do
        expect(result.services.size).to eq(2)
      end

      it "retains result.edges.size" do
        expect(result.edges.size).to eq(1)
      end
    end

    context "when extracts service information" do
      let(:result) { parser.parse(input) }

      it "retains db" do
        db = result.services.find { |s| s.id == "db" }

        expect(db).not_to be_nil
      end

      it "retains db.icon" do
        db = result.services.find { |s| s.id == "db" }

        expect(db.icon).to eq("database")
      end

      it "retains db.label" do
        db = result.services.find { |s| s.id == "db" }

        expect(db.label).to eq("Database")
      end
    end

    context "when extracts edge information" do
      let(:result) { parser.parse(input) }

      it "retains edge.from_id" do
        edge = result.edges.first

        expect(edge.from_id).to eq("db")
      end

      it "retains edge.to_id" do
        edge = result.edges.first

        expect(edge.to_id).to eq("server")
      end
    end
  end

  context "with groups" do
    let(:input) do
      <<~MERMAID
        architecture-beta
                    group api(cloud)[API]

                    service db(database)[Database] in api
                    service server(server)[Server] in api
      MERMAID
    end

    context "when parsing groups" do
      let(:result) { parser.parse(input) }

      it "retains result.groups.size" do
        expect(result.groups.size).to eq(1)
      end

      it "retains group.id" do
        group = result.groups.first

        expect(group.id).to eq("api")
      end

      it "retains group.label" do
        group = result.groups.first

        expect(group.label).to eq("API")
      end

      it "retains group.icon" do
        group = result.groups.first

        expect(group.icon).to eq("cloud")
      end
    end

    it "associates services with groups" do
      result = parser.parse(input)

      db = result.services.find { |s| s.id == "db" }
      expect(db.group_id).to eq("api")
    end
  end

  context "with nested groups" do
    let(:input) do
      <<~MERMAID
        architecture-beta
                    group api[API]
                    group public[Public API] in api
                    group private[Private API] in api

                    service serv1(server)[Server] in public
                    service serv2(server)[Server] in private
      MERMAID
    end

    context "when parsing nested group hierarchy" do
      let(:result) { parser.parse(input) }

      it "retains result.groups.size" do
        expect(result.groups.size).to eq(3)
      end

      it "retains public_group.parent_id" do
        public_group = result.groups.find { |g| g.id == "public" }

        expect(public_group.parent_id).to eq("api")
      end

      it "retains private_group.parent_id" do
        private_group = result.groups.find { |g| g.id == "private" }

        expect(private_group.parent_id).to eq("api")
      end
    end
  end

  context "with title and accessibility" do
    let(:input) do
      <<~MERMAID
        architecture-beta
                  title Simple Architecture Diagram
                  accTitle: Accessibility Title
                  accDescr: Accessibility Description

                  service db(database)[Database]
      MERMAID
    end

    context "when parsing metadata" do
      let(:result) { parser.parse(input) }

      it "retains result.title" do
        expect(result.title).to eq("Simple Architecture Diagram")
      end

      it "retains result.acc_title" do
        expect(result.acc_title).to eq("Accessibility Title")
      end

      it "retains result.acc_descr" do
        expect(result.acc_descr).to eq("Accessibility Description")
      end
    end
  end

  context "with directional edges" do
    let(:input) do
      <<~MERMAID
        architecture-beta
                    service api(server)[API]
                    service db(database)[Database]

                    api:R --> L:db
      MERMAID
    end

    context "when parsing edge direction hints" do
      let(:result) { parser.parse(input) }

      it "retains edge.from_position" do
        edge = result.edges.first

        expect(edge.from_position).to eq("R")
      end

      it "retains edge.to_position" do
        edge = result.edges.first

        expect(edge.to_position).to eq("L")
      end
    end
  end

  context "with edge labels" do
    let(:input) do
      <<~MERMAID
        architecture-beta
                    service ui(browser)[UI]
                    service api(server)[API]

                    ui:R --> L:api: HTTP
      MERMAID
    end

    it "parses edge labels" do
      result = parser.parse(input)

      edge = result.edges.first
      expect(edge.label).to eq("HTTP")
    end
  end

  context "with a bare service (no icon, no label, no group)" do
    # architecture/should_handle_a_simple_radar_definition-0a5b3a96
    # and architecture/xss_spec-3828c690: "service db" with nothing else.
    let(:input) { "architecture-beta\n            service db\n" }

    context "when parsing the service with nil icon and label" do
      let(:result) { parser.parse(input) }

      it "retains service.id" do
        service = result.services.first

        expect(service.id).to eq("db")
      end

      it "retains service.icon" do
        service = result.services.first

        expect(service.icon).to be_nil
      end

      it "retains service.label" do
        service = result.services.first

        expect(service.label).to be_nil
      end

      it "retains service.group_id" do
        service = result.services.first

        expect(service.group_id).to be_nil
      end
    end
  end

  context "with a multiline accessibility description block" do
    # architecture/should_handle_multiline_accessibility_descriptio-97345398
    # and architecture/architecture_test-42e45099: accDescr { ... } rather
    # than the single-line accDescr: form.
    let(:input) do
      <<~MERMAID
        architecture-beta
            accDescr {
                Accessibility Description
            }
      MERMAID
    end

    it "parses the block content as the accessibility description" do
      result = parser.parse(input)

      expect(result.acc_descr).to eq("Accessibility Description")
    end
  end

  context "with a multiline accessibility description block spanning several lines" do
    # `(rbrace.absent? >> any).repeat.as(:acc_descr)` matches non-empty
    # content as one Slice, not an Array of per-line slices - this spec
    # exercises extract_text's String/else branch, not its Array branch.
    # The Array branch only fires on the zero-match `[]` case below; see
    # "extract_text's Array branch, called directly" for direct coverage.
    let(:input) do
      <<~MERMAID
        architecture-beta
            accDescr {
                Line one here
                Line two here
            }
      MERMAID
    end

    it "joins every line of the block into one description" do
      result = parser.parse(input)

      expect(result.acc_descr).to eq("Line one here\n        Line two here")
    end
  end

  context "with an empty multiline accessibility description block" do
    # Parslet's `.repeat` (no minimum) yields [] rather than a slice when
    # it matches zero characters, and extract_text used to stringify that
    # array literally as "[]" instead of treating it as no text.
    let(:input) do
      <<~MERMAID
        architecture-beta
            accDescr {}
            service a(server)[A]
      MERMAID
    end

    it "parses the empty block as an empty description, not the literal \"[]\"" do
      result = parser.parse(input)

      expect(result.acc_descr).to eq("")
    end
  end

  describe "Sirena::Parser::Builders::Architecture#extract_text's Array branch, called directly" do
    # No grammar rule in this parser ever hands extract_text a multi-
    # element Array (see the comment above) - this calls the private
    # method directly to lock down the join behavior anyway.
    let(:transform) { Sirena::Parser::Builders::Architecture.new }

    it "joins a multi-element array of strings" do
      # Each element is stripped by extract_text's own recursion before
      # the join, so a leading/trailing space on an element is lost -
      # exercise that here rather than assume whitespace survives.
      result = transform.send(:extract_text, ["Line one", "  Line two  "])

      expect(result).to eq("Line oneLine two")
    end
  end

  context "with a junction" do
    # architecture/architecture_spec-f1819a63: junctions route edges
    # between services and carry no icon or label of their own.
    let(:input) do
      <<~MERMAID
        architecture-beta
                    group hub(cloud)[Hub]
                    service left(server)[Left] in hub
                    service right(server)[Right] in hub

                    junction mid in hub
                    left:R -- L:mid
                    mid:R -- L:right
      MERMAID
    end

    context "when parsing the junction separately from services and " \
            "groups" do
      let(:result) { parser.parse(input) }

      it "retains result.junctions.size" do
        expect(result.junctions.size).to eq(1)
      end

      it "retains junction.id" do
        junction = result.junctions.first

        expect(junction.id).to eq("mid")
      end

      it "retains junction.group_id" do
        junction = result.junctions.first

        expect(junction.group_id).to eq("hub")
      end

      it "retains result.services.map id" do
        expect(result.services.map(&:id)).to eq(%w[left right])
      end
    end

    it "parses edges that reference the junction as an endpoint" do
      result = parser.parse(input)

      expect(result.edges.map { |e| [e.from_id, e.to_id] })
        .to eq([%w[left mid], %w[mid right]])
    end
  end

  context "with corpus fixtures" do
    let(:arch_dir) do
      File.expand_path("../../mermaid/architecture", __dir__)
    end

    context "when parsing fixture 011 (a group full of junctions)" do
      let(:source) { File.read(File.join(arch_dir, file)) }
      let(:result) { parser.parse(source) }
      let(:file) { "architecture_spec-f1819a63.mmd" }

      it "retains result.junctions.map id" do
        expect(result.junctions.map(&:id))
          .to eq(%w[mid 1Leftofmid 2Leftofmid 3Leftofmid 1RightOfMid 2RightOfMid 3RightOfMid])
      end
    end

    context "when parsing fixture 017 (a bare service)" do
      let(:source) { File.read(File.join(arch_dir, file)) }
      let(:result) { parser.parse(source) }
      let(:file) { "should_handle_a_simple_radar_definition-0a5b3a96.mmd" }

      it "retains result.services.map id" do
        expect(result.services.map(&:id)).to eq(["db"])
      end
    end

    context "when parsing fixture 021 (multiline accDescr)" do
      let(:source) { File.read(File.join(arch_dir, file)) }
      let(:result) { parser.parse(source) }
      let(:file) do
        "should_handle_multiline_accessibility_descriptio-97345398.mmd"
      end

      it "retains result.acc_descr" do
        expect(result.acc_descr).to eq("Accessibility Description")
      end
    end

    context "when parsing fixture 028 (title, accTitle and multiline " \
            "accDescr together)" do
      let(:source) do
        File.read(File.join(arch_dir, "architecture_test-42e45099.mmd"))
      end
      let(:result) { parser.parse(source) }

      it "retains result.title" do
        expect(result.title).to eq("sample title")
      end

      it "retains result.acc_title" do
        expect(result.acc_title).to eq("sample accTitle")
      end

      it "retains result.acc_descr" do
        expect(result.acc_descr).to eq("sample accDescr")
      end
    end

    context "when parsing fixture 029 (a bare service inside a group)" do
      let(:source) { File.read(File.join(arch_dir, file)) }
      let(:result) { parser.parse(source) }
      let(:file) { "xss_spec-3828c690.mmd" }

      it "retains result.services.map id" do
        expect(result.services.map(&:id)).to eq(["db"])
      end

      it "retains result.services.first.icon" do
        expect(result.services.first.icon).to be_nil
      end
    end
  end
end
