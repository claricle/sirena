# frozen_string_literal: true

require 'fileutils'
require 'stringio'

# Helpers for spec/scripts/corpus_sweep_spec.rb; `seed` needs a `root` example.
module CorpusSweepSpecHelpers
  def seed(type, name, source)
    FileUtils.mkdir_p(File.join(root, type))
    File.write(File.join(root, type, name), source)
  end

  def engine_returning(output)
    instance_double(Sirena::Engine, render: output).tap do |engine|
      allow(Sirena::Engine).to receive(:new).and_return(engine)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
