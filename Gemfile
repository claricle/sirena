# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'benchmark'
gem 'rake'
# corpus_sweep and the kanban integration spec both parse SVG output.
gem 'rexml'
gem 'rspec'
# Exact versions on purpose. A floating rubocop turns a green lane red on
# a release nobody here made, and "0 offences" only means something if the
# tool that said it is the same tool tomorrow. Gemfile.lock is gitignored,
# so these four lines are the only thing holding the lint gems still; the
# gems they pull in (rubocop-ast, parser, prism) still resolve freshly.
gem "rubocop", "1.89.0"
gem "rubocop-performance", "1.26.1", require: false
gem "rubocop-rake", "0.7.1", require: false
gem "rubocop-rspec", "3.10.2", require: false
gem 'svg_conform', '~> 0.2.0'
