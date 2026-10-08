# frozen_string_literal: true

# Restores the notation registry after each example, so a spec can register
# fakes. The registry has no public unregister.
RSpec.shared_context "with an isolated notation registry" do
  around do |example|
    entries = Sirena::Notation.send(:entries)
    saved = entries.dup
    example.run
  ensure
    entries.replace(saved)
  end
end
