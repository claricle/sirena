# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  subject(:dimensions) do
    svg = Sirena.render(source, notation: :plantuml)
    document = Nokogiri::XML(svg).tap(&:remove_namespaces!)
    rectangle = document.at_xpath("//g[@id='class-#{class_name}']/rect")
    %w[width height].map { |name| rectangle[name].to_f }
  end

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  context "with members" do
    let(:class_name) { "Foo" }
    let(:source) do
      <<~PLANTUML
        @startuml
        class Foo {
          + foo
          - bar
        }
        @enduml
      PLANTUML
    end

    it "uses PlantUML's member row cadence" do
      expected = [
        be_within(0.01).of(56.7051), be_within(0.01).of(80.9766)
      ]
      expect(dimensions).to match(expected)
    end
  end

  context "with a visible stereotype" do
    let(:class_name) { "Access" }
    let(:source) do
      <<~PLANTUML
        @startuml
        hide <<focus>> stereotype
        class Access <<Entity>> <<focus>>
        @enduml
      PLANTUML
    end

    it "uses PlantUML's stereotype chrome" do
      expected = [
        be_within(0.01).of(78.0742), be_within(0.01).of(56.6211)
      ]
      expect(dimensions).to match(expected)
    end
  end
end
