# frozen_string_literal: true

require 'spec_helper'

# sirena/02: the `xml do` mapping on Text, Tspan, Group and Document was dead
# for output -- to_xml is hand-written and never reads it -- but it was the
# only thing that made `from_xml` work on these four. Deleting it is a real
# behaviour change even though rendered output never moves: `from_xml` used
# to succeed on all four (and did, in the from_xml specs this PR removes) and
# now raises. Nothing else in this diff proves that -- it's the one place a
# whole-file revert of lib/sirena/svg/{text,tspan,group,document}.rb produces
# a genuinely different outcome from the code as shipped.
RSpec.describe 'SVG classes with no lutaml xml mapping' do # rubocop:disable RSpec/DescribeClass
  [
    [Sirena::Svg::Text, '<text/>'],
    [Sirena::Svg::Tspan, '<tspan/>'],
    [Sirena::Svg::Group, '<g/>'],
    [Sirena::Svg::Document, '<svg/>']
  ].each do |klass, xml|
    it "refuses .from_xml on #{klass.name.split('::').last}, having no xml mapping left to parse with" do
      expect { klass.from_xml(xml) }.to raise_error(Lutaml::Model::TypeOnlyMappingError)
    end
  end
end
