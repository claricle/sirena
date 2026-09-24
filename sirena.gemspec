# frozen_string_literal: true

require_relative 'lib/sirena/version'

Gem::Specification.new do |spec|
  spec.name          = 'sirena'
  spec.version       = Sirena::VERSION
  spec.authors       = ['Ribose Inc.']
  spec.email         = ['open.source@ribose.com']

  spec.summary       = 'Pure Ruby Mermaid diagram renderer with SVG output'
  spec.description   = 'Sirena is a pure Ruby implementation of Mermaid ' \
                       'diagram rendering. It parses Mermaid syntax and ' \
                       'generates SVG output using Parslet grammars and ' \
                       'a built-in fallback grid layout. Supports 24 diagram types: flowcharts, ' \
                       'sequence, class, state, ER, C4, block, architecture, ' \
                       'Gantt, timeline, Git graph, mindmap, Kanban, user journey, ' \
                       'pie, quadrant, radar, XY charts, requirement, Sankey, ' \
                       'packet, treemap, info, and error displays.'
  spec.homepage      = 'https://github.com/claricle/sirena'
  spec.license       = 'BSD-2-Clause'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    (Dir['{lib,exe}/**/*'] + Dir['README.adoc'] + Dir['LICENSE*'] + Dir['CHANGELOG*'])
      .select { |f| File.file?(f) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Not yet called (TODO.foundation/14 tracks wiring it into Engine#layout_graph).
  spec.add_dependency 'elkrb', '~> 1.0'
  spec.add_dependency 'kramdown', '~> 2.5'
  # From 0.8.32, a `collection: true` attribute reads back as an Array even
  # after a scalar assignment; read it through Array(...), never raw.
  spec.add_dependency 'lutaml-model', '~> 0.8.0'
  spec.add_dependency 'plurimath-parslet', '~> 3.0'
  spec.add_dependency 'thor'
end
