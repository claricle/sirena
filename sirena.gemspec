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
                       'ELK layout. Supports 24 diagram types: flowcharts, ' \
                       'sequence, class, state, ER, C4, block, architecture, ' \
                       'Gantt, timeline, Git graph, mindmap, Kanban, user journey, ' \
                       'pie, quadrant, radar, XY charts, requirement, Sankey, ' \
                       'packet, treemap, info, and error displays.'
  spec.homepage      = 'https://github.com/claricle/sirena'
  spec.license       = 'BSD-2-Clause'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/})
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # TODO: Uncomment when elkrb is available
  # spec.add_dependency "elkrb"
  spec.add_dependency 'lutaml-model', '~> 0.7'
  spec.add_dependency 'moxml'
  spec.add_dependency 'plurimath-parslet', '~> 3.0'
  spec.add_dependency 'thor'

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
end
