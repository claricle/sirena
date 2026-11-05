# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "sirena/notation/plantuml"

RSpec::Matchers.define_negated_matcher :not_include, :include

RSpec.describe Sirena::Notation::PlantUML::Include do
  let(:root) { File.realpath(Dir.mktmpdir("sirena-include")) }
  let(:docs) { File.join(root, "docs") }
  let(:libs) { File.join(root, "libs") }
  let(:error_class) { described_class::Error }

  before do
    FileUtils.mkdir_p([docs, libs])
    write("docs/sequences.puml", <<~PUML)
      @startuml
      Alice -> Bob : Request 1
      @enduml

      @startuml
      Bob -> Alice : Response 2
      @enduml
    PUML
    write("docs/subpart.puml", <<~PUML)
      @startuml
      A -> A : stuff1
      !startsub BASIC
      B -> B : stuff2
      !endsub
      C -> C : stuff3
      !startsub BASIC
      D -> D : stuff4
      !endsub
      @enduml
    PUML
  end

  after { FileUtils.remove_entry(root) }

  def write(relative, text)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def expand(body, **options)
    described_class.expand("@startuml\n#{body}\n@enduml\n", **options)
  end

  describe "block selection (PlantUML 1.2026.6 draws the first block)" do
    ["!1", "!2", "!7", "!NOPE", ""].each do |selector|
      it "takes the first block for `!include sequences.puml#{selector}`" do
        out = expand("!include sequences.puml#{selector}", base_dir: docs)

        expect(out).to include("Alice -> Bob : Request 1")
          .and(not_include("Response 2"))
      end
    end

    context "with ids on the blocks" do
      before do
        write("docs/components.puml", "@startuml(id=FRONTEND)\nWeb App\n" \
                                      "@enduml\n@startuml(id=BACKEND)\n" \
                                      "Database\n@enduml\n")
      end

      it "takes the first block for `!BACKEND`" do
        out = expand("!include components.puml!BACKEND", base_dir: docs)

        expect(out).to include("Web App").and(not_include("Database"))
      end
    end

    it "takes a file without any @start tag whole" do
      write("docs/plain.puml", "A -> B\nB -> C\n")

      expect(expand("!include plain.puml", base_dir: docs))
        .to include("A -> B").and(include("B -> C"))
    end

    it "takes an unterminated first block to the end of the file" do
      write("docs/open.puml", "@startuml\nA -> B\n")

      expect(expand("!include open.puml", base_dir: docs)).to include("A -> B")
    end
  end

  describe "!includesub" do
    it "keeps every stretch of the named sub, in file order" do
      out = expand("!includesub subpart.puml!BASIC", base_dir: docs)

      expect(out.lines.map(&:strip) & ["B -> B : stuff2", "D -> D : stuff4"])
        .to eq(["B -> B : stuff2", "D -> D : stuff4"])
    end

    it "leaves the lines outside the sub and the markers out" do
      out = expand("!includesub subpart.puml!BASIC", base_dir: docs)

      expect(out).to not_include("stuff1").and(not_include("stuff3"))
        .and(not_include("startsub")).and(not_include("endsub"))
    end

    it "refuses a sub name the file does not define" do
      expect { expand("!includesub subpart.puml!NOPE", base_dir: docs) }
        .to raise_error(error_class, "cannot include subpart.puml!NOPE")
    end

    it "keeps the lines of a plain !include, markers dropped" do
      out = expand("!include subpart.puml!BASIC", base_dir: docs)

      expect(out).to include("A -> A", "B -> B", "C -> C", "D -> D")
        .and(not_include("startsub", "endsub"))
    end

    it "drops the markers from the source being rendered" do
      source = "@startuml\n!startsub X\nA -> B\n!endsub\n@enduml\n"

      out = described_class.expand(source)

      expect(out).to include("A -> B").and(not_include("startsub"))
    end
  end

  describe "search order" do
    before do
      write("docs/pick.puml", "@startuml\nBeside -> Beside\n@enduml\n")
      write("libs/pick.puml", "@startuml\nLibrary -> Library\n@enduml\n")
      write("libs/only.puml", "@startuml\nLibOnly -> LibOnly\n@enduml\n")
    end

    it "prefers the file beside the source over the include path" do
      out = expand("!include pick.puml", base_dir: docs, include_path: [libs])

      expect(out).to include("Beside").and(not_include("Library"))
    end

    it "falls back to the include path" do
      out = expand("!include only.puml", base_dir: docs, include_path: [libs])

      expect(out).to include("LibOnly")
    end

    it "splits a path-separated include path" do
      path = [root, libs].join(File::PATH_SEPARATOR)

      expect(expand("!include only.puml", include_path: path))
        .to include("LibOnly")
    end

    it "reads a nested include relative to the including file" do
      write("docs/deep/outer.puml", "@startuml\n!include inner.puml\n@enduml\n")
      write("docs/deep/inner.puml", "@startuml\nInner -> Inner\n@enduml\n")

      expect(expand("!include deep/outer.puml", base_dir: docs))
        .to include("Inner -> Inner")
    end

    it "reads a subdirectory path under the source directory" do
      write("docs/test_include_path/a.puml", "@startuml\nSub -> Sub\n@enduml\n")

      expect(expand("!include test_include_path/a.puml!1", base_dir: docs))
        .to include("Sub -> Sub")
    end
  end

  describe "failures" do
    it "names a file that cannot be found" do
      expect { expand("!include nofile.puml", base_dir: docs) }
        .to raise_error(error_class, "cannot include nofile.puml")
    end

    it "cannot read a relative path when it has no directory" do
      expect { expand("!include sequences.puml") }
        .to raise_error(error_class, /cannot include sequences.puml/)
    end

    it "refuses a URL" do
      expect { expand("!include https://example.test/a.puml") }
        .to raise_error(error_class, /URL is not supported/)
    end

    it "stops a file that includes itself" do
      write("docs/loop.puml", "@startuml\n!include loop.puml\n@enduml\n")

      expect { expand("!include loop.puml", base_dir: docs) }
        .to raise_error(error_class, /nests too deeply/)
    end

    it "ignores a directory that does not exist" do
      expect do
        expand("!include sequences.puml", base_dir: docs,
                                          include_path: "#{root}/gone")
      end
        .not_to raise_error
    end
  end

  describe "path-traversal guard" do
    before { write("secret.puml", "@startuml\nSecret -> Secret\n@enduml\n") }

    it "refuses ../ out of the source directory" do
      expect { expand("!include ../secret.puml", base_dir: docs) }
        .to raise_error(error_class, "cannot include ../secret.puml")
    end

    it "refuses an absolute path outside every root" do
      expect { expand("!include #{root}/secret.puml", base_dir: docs) }
        .to raise_error(error_class, /cannot include/)
    end

    it "refuses a symlink that leaves the roots" do
      File.symlink(File.join(root, "secret.puml"), File.join(docs, "link.puml"))

      expect { expand("!include link.puml", base_dir: docs) }
        .to raise_error(error_class, "cannot include link.puml")
    end

    it "refuses a sibling directory sharing the root's name as a prefix" do
      write("docs-extra/x.puml", "@startuml\nX -> X\n@enduml\n")

      expect { expand("!include ../docs-extra/x.puml", base_dir: docs) }
        .to raise_error(error_class, /cannot include/)
    end

    it "refuses ../ from a nested include" do
      write("docs/deep/outer.puml",
            "@startuml\n!include ../../secret.puml\n@enduml\n")

      expect { expand("!include deep/outer.puml", base_dir: docs) }
        .to raise_error(error_class, "cannot include ../../secret.puml")
    end

    it "allows an absolute path inside a root" do
      expect(expand("!include #{docs}/sequences.puml", base_dir: docs))
        .to include("Request 1")
    end

    it "refuses a directory in place of a file" do
      expect { expand("!include .", base_dir: docs) }
        .to raise_error(error_class, "cannot include .")
    end
  end

  describe "sources without a directive" do
    it "returns the source untouched" do
      source = "@startuml\nA -> B\n@enduml\n"

      expect(described_class.expand(source)).to equal(source)
    end
  end
end
