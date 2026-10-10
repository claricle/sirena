# frozen_string_literal: true

# Lets one example say "raises, and leaves X alone" as a single expectation:
#   expect { call }.to raise_error(Foo).and(not_change { state })
RSpec::Matchers.define_negated_matcher :not_change, :change
