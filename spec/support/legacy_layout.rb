# frozen_string_literal: true

module SpecSupport
  # A layout that defines #build_graph and nothing else, the shape every
  # layout has until it is converted. Keep it until TODO.architecture item
  # 06 deletes the legacy branch of Layout::Base#call.
  class LegacyLayout < Sirena::Layout::Base
    def build_graph(_diagram)
      { id: 'root', children: [{ id: 'a', width: 50, height: 30 }] }
    end
  end
end
