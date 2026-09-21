# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'

# scripts/corpus_sweep.rb is a program that sweeps on load, so it runs as a
# subprocess. Its `info` cases all render well-formed SVG, which makes the
# unpatched run the control: the only difference in the seeded run is that
# Engine#render returns SVG-shaped output that is not XML.
RSpec.describe 'scripts/corpus_sweep.rb', type: :task do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:info_cases) { Dir.glob(File.join(root, 'spec', 'mermaid', 'info', '*.mmd')).size }

  # `<img src=` opens a tag that never closes, the shape of the XSS corpus case.
  let(:malformed_svg) do
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><text>Alice<img src=</text></svg>'
  end

  # Returns [stdout, status]; stderr is not part of what is asserted.
  let(:sweep_info) do
    lambda do |prelude = nil|
      args = prelude ? ['-r', prelude] : []
      out, _err, status = Open3.capture3(RbConfig.ruby, *args, File.join(root, 'scripts', 'corpus_sweep.rb'),
                                         '--failing', 'info', chdir: root)
      [out, status]
    end
  end

  it 'has info cases to sweep' do
    expect(info_cases).to be_positive
  end

  it 'passes every info case when the renderer emits well-formed SVG' do
    out, status = sweep_info.call

    expect(status).to be_success
    expect(out).to include("TOTAL: #{info_cases}/#{info_cases}")
    expect(out).not_to match(/^fail:/)
  end

  it 'reports a failure, not a pass, for SVG-shaped output that is not XML' do
    Dir.mktmpdir do |dir|
      prelude = File.join(dir, 'seed_malformed.rb')
      File.write(prelude, <<~RUBY)
        require 'bundler/setup'
        $LOAD_PATH.unshift(#{File.join(root, 'lib').inspect})
        require 'sirena'
        Sirena::Engine.prepend(Module.new { def render(*) = #{malformed_svg.inspect} })
      RUBY

      out, = sweep_info.call(prelude)

      expect(out).to include("TOTAL: 0/#{info_cases}")
      expect(out.scan(%r{^fail: info/}).size).to eq(info_cases)
    end
  end
end
