# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe "Treemap blank bodies" do
  it "renders a blank body" do
    expect(Sirena.render("treemap-beta\n\n")).to start_with("<svg")
  end
end
