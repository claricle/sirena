# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Base do
  subject(:diagram) { described_class.new }

  describe "#valid?" do
    it "requires subclasses to implement validation" do
      expect { diagram.valid? }
        .to raise_error(
          NotImplementedError,
          "Sirena::Diagram::Base must implement #valid?",
        )
    end
  end

  describe "#diagram_type" do
    it "requires subclasses to identify their diagram type" do
      expect { diagram.diagram_type }
        .to raise_error(
          NotImplementedError,
          "Sirena::Diagram::Base must implement #diagram_type",
        )
    end
  end
end
