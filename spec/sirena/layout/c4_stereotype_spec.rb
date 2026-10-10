# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4Stereotype do
  {
    "Person" => "<<person>>",
    "Person_Ext" => "<<external_person>>",
    "SystemDb" => "<<system_db>>",
    "ContainerQueue_Ext" => "<<external_container_queue>>",
    "" => nil,
    nil => nil,
  }.each do |type, caption|
    it "captions #{type.inspect} as #{caption.inspect}" do
      expect(described_class.text(type)).to eq(caption)
    end
  end
end
