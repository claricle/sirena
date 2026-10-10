# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Parser do
  let(:parser) { described_class.new }
  let(:unsupported) { Sirena::Notation::PlantUML::UnsupportedConstructError }

  it "refuses content after the closing directive" do
    source = "@startuml\nA -> B\n@enduml\nB -> A\n"

    expect { parser.parse(source) }
      .to raise_error(unsupported, /content after @enduml/)
  end

  it "refuses a named opening directive" do
    expect { parser.parse("@startuml sequence\n@enduml\n") }
      .to raise_error(unsupported, /diagram name/)
  end

  it "reports a non-PlantUML first statement as an unknown diagram" do
    expect { parser.parse("A -> B\n") }
      .to raise_error(Sirena::Engine::DiagramTypeError, /Unable to detect/)
  end

  it "reports an empty source as an unknown diagram" do
    expect { parser.parse("") }
      .to raise_error(Sirena::Engine::DiagramTypeError, /Unable to detect/)
  end

  it "refuses a positioned note on a parallel row" do
    source = "@startuml\n!pragma teoz true\nA -> B\n& note top: x\n@enduml\n"

    expect { parser.parse(source) }.to raise_error(unsupported, /note/)
  end
end
