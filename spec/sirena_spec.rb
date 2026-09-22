# frozen_string_literal: true

require 'spec_helper'

# lib/sirena.rb used to carry a second `def self.render` written after
# `module Sirena`'s closing `end` -- syntactically outside the module, so
# it defined a singleton method on the real top-level `main` object shared
# by the whole process instead of on `Sirena`. It shadowed nothing (nobody
# calls bare `render` at the top level) and raised `NameError: uninitialized
# constant Engine` if anyone ever did, because `Engine` unqualified does not
# resolve to `Sirena::Engine` outside the module.
RSpec.describe Sirena do
  it 'does not leak a render method onto the top-level main object' do
    expect(TOPLEVEL_BINDING.receiver.respond_to?(:render, true)).to be false
  end
end
