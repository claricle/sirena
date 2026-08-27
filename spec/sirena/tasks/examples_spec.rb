# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'rake'
require 'tmpdir'
require 'yaml'

# The generation task deletes files. Nothing else in the suite calls it: the
# conformance gate reads what is on disk, so it catches an orphan that already
# shipped and says nothing about whether the sweeper removes one. Disabling the
# sweep left the whole suite green, which is why this exists.
#
# The rake file is loaded rather than reimplemented, so the helpers under test
# are the ones the task runs. Loading it defines tasks into the default Rake
# application; none is invoked here.
TASKS_RAKE_FILE = File.expand_path('../../../lib/tasks/examples.rake', __dir__)
load TASKS_RAKE_FILE unless defined?(ExampleTasks)

RSpec.describe ExampleTasks do
  around do |example|
    Dir.mktmpdir('sirena-examples') do |dir|
      @examples_dir = dir
      example.run
    end
  end

  attr_reader :examples_dir

  def write(relative_path, content = 'x')
    path = File.join(examples_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  describe '.remove_orphan_svgs' do
    it 'keeps an SVG whose source is still there' do
      write('flowchart/01-basic.mmd')
      svg = write('flowchart/01-basic.svg')

      described_class.remove_orphan_svgs(examples_dir)

      expect(File).to exist(svg)
    end

    it 'removes an SVG whose source is gone' do
      orphan = write('flowchart/02-deleted.svg')

      described_class.remove_orphan_svgs(examples_dir)

      expect(File).not_to exist(orphan)
    end

    # The gemspec packages every SVG under examples/ at any depth, so a sweep
    # one level deep leaves exactly the orphans a human then deletes by hand.
    it 'removes an orphan sitting directly under examples' do
      orphan = write('stray_example.svg')

      described_class.remove_orphan_svgs(examples_dir)

      expect(File).not_to exist(orphan)
    end

    it 'leaves files that are not SVGs alone' do
      kept = write('flowchart/notes.txt')

      described_class.remove_orphan_svgs(examples_dir)

      expect(File).to exist(kept)
    end
  end

  describe '.theme_for' do
    it 'reads the theme its metadata names' do
      mmd = write('flowchart/01-basic.mmd')
      write('flowchart/01-basic.yml', YAML.dump('theme' => 'dark'))

      expect(described_class.theme_for(mmd)).to eq('dark')
    end

    it 'falls back to default when the source carries no metadata' do
      mmd = write('flowchart/01-basic.mmd')

      expect(described_class.theme_for(mmd)).to eq('default')
    end

    it 'falls back to default when the metadata names no theme' do
      mmd = write('flowchart/01-basic.mmd')
      write('flowchart/01-basic.yml', YAML.dump('title' => 'Basic'))

      expect(described_class.theme_for(mmd)).to eq('default')
    end
  end
end
