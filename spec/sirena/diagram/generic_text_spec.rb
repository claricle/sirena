# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::GenericText do
  describe ".display" do
    it "draws every generic pair with angle brackets" do
      expect(described_class.display("Map~K~ and List~V~"))
        .to eq("Map<K> and List<V>")
    end
  end

  describe ".display_member" do
    it "preserves package visibility while drawing generics and entities" do
      expect(described_class.display_member("~List~T~ &lt;x&gt;"))
        .to eq("~List<T> <x>")
    end

    it "draws ordinary members without treating generics as visibility" do
      expect(described_class.display_member("List~T~ &amp; value"))
        .to eq("List<T> & value")
    end
  end
end
