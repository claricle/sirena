# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def rendered_dimensions
    id = "resources.vega.nonreg.group2904.diamond_at_tail--bb82b36b91be"
    source = File.read("spec/plantuml/class/#{id}.puml")
    document = Nokogiri::XML(Sirena.render(source, notation: :plantuml))
    document.remove_namespaces!
    %w[Company Person Car].to_h do |name|
      rectangle = document.at_xpath("//g[@id='class-#{name}']/rect")
      dimensions = [rectangle["width"].to_f, rectangle["height"].to_f]
      [name, dimensions]
    end
  end

  def expected_dimensions
    height = be_within(0.01).of(48.0)
    {
      "Company" => [be_within(0.01).of(95.9023), height],
      "Person" => [be_within(0.01).of(77.6914), height],
      "Car" => [be_within(0.01).of(55.1465), height],
    }
  end

  it "keeps intrinsic Smetana chrome for heterogeneous empty classes" do
    expect(rendered_dimensions).to match(expected_dimensions)
  end
end
