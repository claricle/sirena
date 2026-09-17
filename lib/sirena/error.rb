# frozen_string_literal: true

module Sirena
  # Base class for every Sirena::Error subclass across the pipeline (parser,
  # transform, renderer, engine). Its own file -- like version.rb -- so a
  # component's base.rb can require_relative it directly and load standalone
  # (`require "sirena/parser"` etc.) without first loading the whole
  # lib/sirena.rb require chain.
  class Error < StandardError; end
end
