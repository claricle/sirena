# frozen_string_literal: true

require 'spec_helper'
require 'ripper'

# Conformant by construction, not conformant after a repair pass.
#
# svg_conform ships a remediation engine that rewrites a document until it
# validates. Reaching for it would turn the gate green while leaving the
# generator wrong, and everyone who builds an Svg element directly — a new
# renderer, anything embedding Sirena — would still get a broken document.
# So the whole mechanism is out of bounds at runtime.
#
# A structural check rather than a behavioural one, because the failure mode
# is a call nobody writes a test for.
REMEDIATION_LIB_ROOT = File.expand_path('../../../lib', __dir__)
REMEDIATION_LIB_FILES = Dir.glob(File.join(REMEDIATION_LIB_ROOT, '**', '*.rb')).freeze

# The remediation entry points, and the gem that owns them. Sirena's runtime
# does not depend on svg_conform at all — it is the gate's tool, not the
# renderer's — so naming it anywhere under lib/ is the same finding.
REMEDIATION = /apply_fixes|SvgConform|svg_conform|RemediationEngine|RemediationRunner/

RSpec.describe Sirena::Svg do
  describe 'runtime remediation' do
    # Lexed rather than grepped. Half the files under lib/ explain in a comment
    # why svg_conform rejects a property, and a line-wise grep reads its own
    # documentation as a violation.
    def code_tokens(path)
      Ripper.lex(File.read(path)).reject { |(_position, type, _token)| type == :on_comment }
    end

    def offences
      REMEDIATION_LIB_FILES.flat_map do |path|
        code_tokens(path).filter_map do |(position, _type, token)|
          "#{path.sub("#{REMEDIATION_LIB_ROOT}/", '')}:#{position.first}: #{token}" if token.match?(REMEDIATION)
        end
      end
    end

    # A bare count is not a population guard here: lib/sirena/parser alone
    # holds 72 files, so the glob could lose the whole of lib/sirena/svg —
    # the one place a remediation call would land — and still clear any
    # threshold worth setting. Named against an independent glob instead.
    it 'reads every file under lib/' do
      expect(REMEDIATION_LIB_FILES)
        .to match_array(Dir.glob(File.join(REMEDIATION_LIB_ROOT, '**', '*.rb')))
      expect(REMEDIATION_LIB_FILES)
        .to include(File.join(REMEDIATION_LIB_ROOT, 'sirena', 'svg', 'element.rb'))
    end

    it 'never calls a fixer or a remediation engine' do
      expect(offences).to be_empty, -> { offences.join("\n") }
    end

    it 'does not declare svg_conform as a runtime dependency' do
      gemspec = Gem::Specification.load(File.expand_path('../../../sirena.gemspec', __dir__))

      expect(gemspec.dependencies.map(&:name)).not_to include('svg_conform')
    end
  end
end
