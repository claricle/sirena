# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Parser do
  it "names an unclosed note when the source ends without @enduml" do
    source = "@startuml\nclass A\nnote top of A\none\n"

    expect { described_class.new.parse(source) }
      .to raise_error(Sirena::Parser::ParseError, /note opened on line 3/)
  end

  it "names an unclosed style block when the source ends without @enduml" do
    source = "@startuml\n<style>\n"
    message = /style block opened on line 2/

    expect { described_class.new.parse(source) }
      .to raise_error(Sirena::Parser::ParseError, message)
  end
end
