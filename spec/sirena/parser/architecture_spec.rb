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
  end
end