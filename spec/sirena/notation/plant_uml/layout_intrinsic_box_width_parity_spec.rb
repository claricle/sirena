# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def class_widths(body)
    source = "@startuml\n#{body}\n@enduml\n"
    document = Nokogiri::XML(Sirena.render(source, notation: :plantuml))
    document.remove_namespaces!
    document.xpath("//g[starts-with(@id, 'class-')]").to_h do |group|
      [group["id"].delete_prefix("class-"), group.at_xpath("./rect")["width"].to_f]
    end
  end

  it "keeps member-bearing classes at their intrinsic widths" do
    widths = class_widths(<<~PLANTUML)
      class Short
      class Detailed {
        + aMuchLongerMember: String
      }
    PLANTUML

    expect(widths.fetch("Short")).to be < widths.fetch("Detailed")
  end

  it "keeps intrinsic widths when a rank chain places the classes" do
    widths = class_widths(<<~PLANTUML)
      !pragma layout smetana
      class Short {
        + id: int
      }
      class Detailed {
        + aMuchLongerMember: String
      }
      Short -- Detailed
    PLANTUML

    expect(widths.fetch("Short")).to be < widths.fetch("Detailed")
  end

  it "does not widen a class to the width of its attached note" do
    widths = class_widths(<<~PLANTUML)
      class Short
      note right of Short
        a note that is much wider than the class title
      end note
    PLANTUML

    expect(widths.fetch("Short")).to eq(68.0)
  end
end
