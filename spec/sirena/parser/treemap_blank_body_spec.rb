# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe Sirena, ".render with blank Treemap bodies" do
  it "renders a blank body" do
    expect(described_class.render("treemap-beta\n\n")).to start_with("<svg")
  end
end
