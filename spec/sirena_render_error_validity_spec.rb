# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render error validity" do
    ["Error Diagrams", "error something went wrong"].each do |source|
      it "refuses #{source.inspect}, as Mermaid's detector does" do
        expect { described_class.render("#{source}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    %W[error Error error\n\n].each do |source|
      it "still renders #{source.inspect}" do
        expect(described_class.render(source)).to start_with("<svg")
      end
    end
  end
end
