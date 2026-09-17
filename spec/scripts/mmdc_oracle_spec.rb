# frozen_string_literal: true

require_relative '../support/mermaid_diff_spec_support'
require_relative '../../scripts/mmdc_oracle'

# direct_verdict is exercised indirectly all over mermaid_diff_spec.rb through
# the oracle_verdict helper, but that helper always hands back a successful
# status. This file drives direct_verdict itself so the nonzero-exit path gets
# its own coverage.
RSpec.describe MmdcOracle do
  include MermaidDiffSpecSupport::Helpers

  describe '.direct_verdict' do
    it 'accepts on a successful exit with a valid, non-error SVG' do
      svg = '<svg aria-roledescription="flowchart-v2"><style/></svg>'

      with_svg_file(svg) { |path| expect(described_class.direct_verdict(true, path)).to be(:accepts) }
    end

    it 'rejects on a nonzero exit with a genuine, well-formed rejection page' do
      with_svg_file(syntax_error_svg) { |path| expect(described_class.direct_verdict(false, path)).to be(:rejects) }
    end

    # The bug: `error_page?` is a regex over raw markup, not an XML validity
    # check, so a process that dies mid-write can leave behind a truncated
    # document that still contains the error-role and XHTML-style markers a
    # real rejection page has. That is a crash producing garbage, not mermaid
    # answering "no" — it must not be reported as :rejects.
    it 'reports a crash, not a rejection, for a truncated document that still carries the error markers' do
      truncated = '<svg aria-roledescription="error">' \
                  '<style xmlns="http://www.w3.org/1999/xhtml">.error-icon{fill:#55'

      with_svg_file(truncated) { |path| expect(described_class.direct_verdict(false, path)).to be(:error) }
    end

    it 'errors on a successful exit with a malformed SVG (unchanged existing behaviour)' do
      with_svg_file('not xml') { |path| expect(described_class.direct_verdict(true, path)).to be(:error) }
    end

    it 'is ambiguous on a nonzero exit with no output file at all' do
      Dir.mktmpdir do |dir|
        expect(described_class.direct_verdict(false, File.join(dir, 'missing.svg'))).to be(:ambiguous)
      end
    end
  end
end
