# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/architecture"

RSpec.describe Sirena::Parser::Architecture do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with simple architecture diagram" do
      let(:input) do
        <<~MERMAID
          architecture-beta
                      service db(database)[Database]
                      service server(server)[Server]

                      db L--R server
        MERMAID
      end

      it "parses successfully" do
        result = parser.parse(input)

        expect(result).to be_a(Sirena::Diagram::ArchitectureDiagram)
        expect(result.services.size).to eq(2)
        expect(result.edges.size).to eq(1)
      end

      it "extracts service information" do
        result = parser.parse(input)

        db = result.services.find { |s| s.id == "db" }
        expect(db).not_to be_nil
        expect(db.icon).to eq("database")
        expect(db.label).to eq("Database")
      end

      it "extracts edge information" do
        result = parser.parse(input)

        edge = result.edges.first
        expect(edge.from_id).to eq("db")
        expect(edge.to_id).to eq("server")
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

      it "parses groups" do
        result = parser.parse(input)

        expect(result.groups.size).to eq(1)
        group = result.groups.first
        expect(group.id).to eq("api")
        expect(group.label).to eq("API")
        expect(group.icon).to eq("cloud")
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

      it "parses nested group hierarchy" do
        result = parser.parse(input)

        expect(result.groups.size).to eq(3)

        public_group = result.groups.find { |g| g.id == "public" }
        expect(public_group.parent_id).to eq("api")

        private_group = result.groups.find { |g| g.id == "private" }
        expect(private_group.parent_id).to eq("api")
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

      it "parses metadata" do
        result = parser.parse(input)

        expect(result.title).to eq("Simple Architecture Diagram")
        expect(result.acc_title).to eq("Accessibility Title")
        expect(result.acc_descr).to eq("Accessibility Description")
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

      it "parses edge direction hints" do
        result = parser.parse(input)

        edge = result.edges.first
        expect(edge.from_position).to eq("R")
        expect(edge.to_position).to eq("L")
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
      # spec/mermaid/architecture/017 and 029: "service db" with nothing else.
      let(:input) { "architecture-beta\n            service db\n" }

      it "parses the service with nil icon and label" do
        result = parser.parse(input)

        service = result.services.first
        expect(service.id).to eq("db")
        expect(service.icon).to be_nil
        expect(service.label).to be_nil
        expect(service.group_id).to be_nil
      end
    end

    context "with a multiline accessibility description block" do
      # spec/mermaid/architecture/021 and 028: accDescr { ... } rather than
      # the single-line accDescr: form.
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

    context "with a junction" do
      # spec/mermaid/architecture/011: junctions route edges between
      # services and carry no icon or label of their own.
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

      it "parses the junction separately from services and groups" do
        result = parser.parse(input)

        expect(result.junctions.size).to eq(1)
        junction = result.junctions.first
        expect(junction.id).to eq("mid")
        expect(junction.group_id).to eq("hub")
        expect(result.services.map(&:id)).to eq(%w[left right])
      end

      it "parses edges that reference the junction as an endpoint" do
        result = parser.parse(input)

        expect(result.edges.map { |e| [e.from_id, e.to_id] })
          .to eq([%w[left mid], %w[mid right]])
      end
    end

    context "with corpus fixtures" do
      it "parses fixture 011 (a group full of junctions)" do
        source = File.read("spec/mermaid/architecture/011_rendering_architecture_spec_architecture_10.mmd")

        result = parser.parse(source)

        expect(result.junctions.map(&:id))
          .to eq(%w[mid 1Leftofmid 2Leftofmid 3Leftofmid 1RightOfMid 2RightOfMid 3RightOfMid])
      end

      it "parses fixture 017 (a bare service)" do
        source = File.read("spec/mermaid/architecture/017_parser_should_handle_a_simple_radar_definition_16.mmd")

        result = parser.parse(source)

        expect(result.services.map(&:id)).to eq(["db"])
      end

      it "parses fixture 021 (multiline accDescr)" do
        source = File.read("spec/mermaid/architecture/021_parser_should_handle_multiline_accessibility_description_20.mmd")

        result = parser.parse(source)

        expect(result.acc_descr).to eq("Accessibility Description")
      end

      it "parses fixture 028 (title, accTitle and multiline accDescr together)" do
        source = File.read("spec/mermaid/architecture/028_parsertest_architecture_test_27.mmd")

        result = parser.parse(source)

        expect(result.title).to eq("sample title")
        expect(result.acc_title).to eq("sample accTitle")
        expect(result.acc_descr).to eq("sample accDescr")
      end

      it "parses fixture 029 (a bare service inside a group)" do
        source = File.read("spec/mermaid/architecture/029_spec_xss_spec_28.mmd")

        result = parser.parse(source)

        expect(result.services.map(&:id)).to eq(["db"])
        expect(result.services.first.icon).to be_nil
      end
    end
  end
end