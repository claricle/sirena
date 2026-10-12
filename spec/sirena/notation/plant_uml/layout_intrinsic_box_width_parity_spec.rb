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
      id = group["id"].delete_prefix("class-")
      [id, group.at_xpath("./rect")["width"].to_f]
    end
  end

  def member_classes
    <<~PLANTUML
      class Short
      class Detailed {
        + aMuchLongerMember: String
      }
    PLANTUML
  end

  def linked_member_classes
    <<~PLANTUML
      !pragma layout smetana
      class Short {
        + id: int
      }
      class Detailed {
        + aMuchLongerMember: String
      }
      Short -- Detailed
    PLANTUML
  end

  def noted_class
    <<~PLANTUML
      class Short
      note right of Short
        a note that is much wider than the class title
      end note
    PLANTUML
  end

  it "keeps member-bearing classes at their intrinsic widths" do
    widths = class_widths(member_classes)

    expect(widths.fetch("Short")).to be < widths.fetch("Detailed")
  end

  it "keeps intrinsic widths when a rank chain places the classes" do
    widths = class_widths(linked_member_classes)

    expect(widths.fetch("Short")).to be < widths.fetch("Detailed")
  end

  it "does not widen a class to the width of its attached note" do
    widths = class_widths(noted_class)

    expect(widths.fetch("Short")).to eq(68.0)
  end
end
