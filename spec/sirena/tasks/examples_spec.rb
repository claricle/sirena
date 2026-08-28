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

  # The only thing standing between a source that stops rendering and the gem
  # shipping its stale picture forever. Deleting the call in :generate left the
  # whole suite green before these.
  describe '.handle_failed_svgs' do
    def handle(failures)
      described_class.handle_failed_svgs(failures)
    end

    let(:expected_source) { EXPECTED_UNRENDERABLE_SOURCES.first }
    # Derived, not typed out: naming the source by position and its SVG by
    # hand let a reorder of the constant pair the two up wrongly.
    let(:expected_svg) { expected_source.sub(/\.mmd\z/, '.svg') }

    it 'deletes the stale SVG of a source that is expected not to render' do
      svg = write(expected_svg)

      expect { handle([[expected_source, svg]]) }.to output.to_stdout
      expect(File).not_to exist(svg)
    end

    it 'says nothing when the stale SVG is already gone' do
      missing = File.join(examples_dir, expected_svg)

      expect { handle([[expected_source, missing]]) }.not_to output.to_stdout
    end

    # An unexpected failure is a regression, not a cleanup. Exiting before any
    # delete is what keeps a real breakage from quietly erasing the evidence.
    it 'exits without deleting anything when an unexpected source failed' do
      svg = write('flowchart/01-basic.svg')

      expect { handle([['flowchart/01-basic.mmd', svg]]) }
        .to raise_error(SystemExit).and(output(/Unexpected/).to_stdout)
      expect(File).to exist(svg)
    end

    it "keeps an expected failure's SVG when an unexpected one shares the run" do
      kept = write(expected_svg)
      unexpected_svg = write('flowchart/01-basic.svg')

      expect do
        handle([[expected_source, kept], ['flowchart/01-basic.mmd', unexpected_svg]])
      end.to raise_error(SystemExit).and(output(/Unexpected/).to_stdout)
      expect(File).to exist(kept)
    end

    it 'does nothing when every source rendered' do
      svg = write('flowchart/01-basic.svg')

      expect { handle([]) }.not_to raise_error
      expect(File).to exist(svg)
    end
  end

  # Both helpers above are worth nothing if the task stops calling them, and
  # nothing else can see a deleted call — that is exactly why they went
  # untested. Pinned on the task's source, the way the conformance gate pins
  # the unrenderable list, because the task's body is a Rake proc that runs
  # against the real examples/ tree and cannot be invoked from a spec.
  describe 'the generate task' do
    let(:task_source) { File.read(TASKS_RAKE_FILE) }

    it 'hands every failed render to the cleanup' do
      expect(task_source).to include('ExampleTasks.handle_failed_svgs(failed_renders)')
    end

    it 'sweeps orphans once generation is done' do
      expect(task_source).to include('ExampleTasks.remove_orphan_svgs(examples_dir)')
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
