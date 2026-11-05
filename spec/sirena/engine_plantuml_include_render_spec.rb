# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Engine, "#render" do
  include_context "with an isolated notation registry"

  let(:root) { File.realpath(Dir.mktmpdir("sirena-engine-include")) }
  let(:libs) { File.join(root, "libs") }
  let(:main) { File.join(root, "main.puml") }

  def texts(svg)
    svg.scan(%r{<text[^>]*>([^<]*)</text>}).flatten
  end

  before do
    unless Sirena::Notation.ids.include?(:plantuml)
      Sirena::Notation.register(Sirena::Notation::PlantUML)
    end
    FileUtils.mkdir_p(libs)
    File.write(File.join(root, "sequences.puml"), <<~PUML)
      @startuml
      Alice -> Bob : Request 1
      @enduml

      @startuml
      Bob -> Alice : Response 2
      @enduml
    PUML
    File.write(File.join(libs, "sequences-a.puml"),
               "@startuml\nCarol -> Dave : From path\n@enduml\n")
    File.write(File.join(root, "subpart.puml"), <<~PUML)
      @startuml
      A -> A : stuff1
      !startsub BASIC
      B -> B : stuff2
      !endsub
      @enduml
    PUML
  end

  after { FileUtils.remove_entry(root) }

  def render(body, **options)
    File.write(main, "@startuml\n#{body}\n@enduml\n")
    described_class.new.render(File.read(main), **options)
  end

  it "reads an include beside the file named by :path" do
    svg = render("!include sequences.puml!1", path: main)

    expect(texts(svg)).to include("Request 1").and(satisfy { |t|
      t.none?("Response 2")
    })
  end

  it "reads an include beside :base_dir for a source with no file" do
    svg = render("!include sequences.puml", base_dir: root)

    expect(texts(svg)).to include("Request 1")
  end

  it "reads an !includesub" do
    svg = render("!includesub subpart.puml!BASIC", path: main)

    expect(texts(svg)).to include("stuff2")
  end

  it "searches :include_path after the source directory" do
    svg = render("!include sequences-a.puml!1", path: main,
                                                include_path: [libs])

    expect(texts(svg)).to include("From path")
  end

  it "searches PLANTUML_INCLUDE_PATH like the JAR's include path property" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PLANTUML_INCLUDE_PATH", nil)
      .and_return(libs)

    expect(texts(render("!include sequences-a.puml", path: main)))
      .to include("From path")
  end

  it "raises a Sirena::Error for a file that is not there" do
    expect { render("!include nofile.puml", path: main) }
      .to raise_error(Sirena::Error, "cannot include nofile.puml")
  end

  context "with a file outside the source directory" do
    let(:outside) { "#{root}-outside.puml" }

    before { File.write(outside, "@startuml\nA -> B : leaked\n@enduml\n") }

    after { FileUtils.rm_f(outside) }

    it "refuses to read it" do
      expect { render("!include ../#{File.basename(outside)}", path: main) }
        .to raise_error(Sirena::Error, /cannot include/)
    end
  end

  describe "keywords handed to a notation" do
    let(:seen) { {} }
    let(:recorder) do
      captured = seen
      Module.new do
        extend self

        define_method(:id) { :recorder }
        define_method(:extensions) { %w[.rec].freeze }
        define_method(:types) { [:class_diagram] }
        define_method(:claims?) { |source| source.start_with?("@rec") }
        define_method(:parse) do |_source, base_dir: nil, include_path: nil|
          captured[:base_dir] = base_dir
          captured[:include_path] = include_path
          Sirena::Notation::PlantUML.parse("@startuml\nclass A\n@enduml\n")
        end
      end
    end

    before { Sirena::Notation.register(recorder) }

    it "hands over the directory of :path and the :include_path" do
      described_class.new.render(
        "@rec", path: main, include_path: ["x"], notation: :recorder
      )

      expect(seen).to eq(base_dir: root, include_path: ["x"])
    end

    it "prefers :base_dir over the directory of :path" do
      described_class.new.render(
        "@rec", path: main, base_dir: libs, notation: :recorder
      )

      expect(seen[:base_dir]).to eq(libs)
    end

    it "hands over nothing when the source has no location" do
      described_class.new.render("@rec")

      expect(seen).to eq(base_dir: nil, include_path: nil)
    end
  end
end
