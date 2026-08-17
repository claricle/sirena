# frozen_string_literal: true

require 'spec_helper'
require 'date'

# Rendering must be a pure function of its input.
#
# Two things broke that, and both moved geometry rather than just adding
# noise:
#
#   - anonymous block ids came from rand(10000), whose digit count varies,
#     and that length reached TextMeasurement and moved the SVG width;
#   - gantt read Date.today, which sets the chart's date range and so every
#     x coordinate.
#
# Neither is caught by rendering twice in one process with a pinned clock —
# that passes with both bugs still present. So this file checks a
# behavioural property AND the absence of the calls.
RSpec.describe Sirena::Engine do
  let(:corpus) { File.expand_path('../mermaid', __dir__) }

  def render(source, **options)
    described_class.new(**options).render(source)
  end

  def corpus_source(type, file)
    File.read(File.join(corpus, type, file))
  end

  describe 'the same source renders identically' do
    # One case per shape of the problem: block exercised the rand path,
    # gantt the clock path, flowchart is the ordinary control.
    {
      'block' => '001_rendering_block_spec_block_0.mmd',
      'gantt' => '001_rendering_gantt_spec_gantt_0.mmd',
      'flowchart' => '001_config_0.mmd'
    }.each do |type, file|
      it "is stable across runs for #{type}" do
        source = corpus_source(type, file)
        first = render(source)
        second = render(source)

        expect(first).to eq(second)
      end
    end
  end

  describe 'the clock is an input, not ambient state' do
    let(:source) do
      corpus_source('gantt', '001_rendering_gantt_spec_gantt_0.mmd')
    end
    let(:early) { Date.new(2020, 1, 1) }
    let(:late) { Date.new(2031, 6, 15) }

    it 'renders identically for the same pinned date' do
      first = render(source, today: early)
      second = render(source, today: early)

      expect(first).to eq(second)
    end

    # The assertion a same-clock test cannot make. If gantt still read
    # Date.today, both of these would render against the real date and
    # match, hiding the bug.
    it 'reflects the pinned date, so it is genuinely consumed' do
      expect(render(source, today: early)).not_to eq(render(source, today: late))
    end

    it 'falls back to the real date when none is given' do
      expect(render(source)).to eq(render(source, today: Date.today))
    end

    # A partial date lets Date.parse fill the year from the system clock, so
    # the pin looked consumed while the year came from the wall. The year never
    # reaches the SVG text, and the fixture above only exercises the max-date
    # fallback, so comparing rendered output cannot see this at all. The
    # computed task date can.
    it 'takes the year of a partial date from the pin' do
      years = [early, late].map do |pin|
        source = "gantt\n  dateFormat MM/DD\n  section S\n  T1 : 08/17, 3d\n"
        diagram = Sirena::Parser::GanttParser.new.parse(source)
        transform = Sirena::Transform::GanttTransform.new
        transform.today = pin
        transform.to_graph(diagram)
        diagram.sections.first.tasks.first.calculated_start.year
      end

      expect(years).to eq([early.year, late.year])
    end

    # Pinning must never be the reason a render breaks. Comparing outcomes
    # rather than asserting success keeps this honest about types that are
    # already failing for unrelated reasons.
    it 'never changes whether a diagram type renders at all' do
      differing = Dir.children(corpus).sort.filter_map do |type|
        file = Dir.glob(File.join(corpus, type, '*.mmd')).min
        next unless file

        source = File.read(file)
        next if outcome(source) == outcome(source, today: early)

        "#{type}: #{outcome(source)} unpinned vs #{outcome(source, today: early)} pinned"
      end

      expect(differing).to be_empty, "pinning altered:\n#{differing.join("\n")}"
    end

    def outcome(source, **options)
      render(source, **options)
      :rendered
    rescue StandardError => e
      # Parse errors embed an inspected Parslet::Position, whose object
      # address differs every call and would make any two runs look different.
      "#{e.class}: #{e.message.lines.first.to_s.strip.gsub(/0x[0-9a-f]+/, '0xX')}"
    end
  end

  # The collision that made determinism insufficient on its own: generated
  # ids shared the author's namespace, so an explicit block could overwrite a
  # generated one and take its children out of the SVG.
  describe 'generated ids stay out of the author namespace' do
    it 'keeps an explicit block and a generated block apart' do
      svg = render("block-beta\n  block\n    child\n  end\n  compound_1\n")

      expect(svg).to include('child')
      expect(svg.scan(/id="([^"]*compound[^"]*)"/).flatten.uniq.size).to eq(2)
    end

    # Spacers carry no id into the SVG, so this has to be read off the model.
    it 'names anonymous spaces positionally' do
      diagram = Sirena::Parser::BlockParser.new
        .parse("block-beta\n  A\n  space\n  B\n")
      spaces = diagram.blocks.select { |b| b.block_type == 'space' }

      expect(spaces.map(&:id)).to eq(['space-2'])
    end
  end

  # Structural half. Two matching random draws are only probabilistic, and a
  # clock read hides behind a pinned clock. The absence of the call holds.
  describe 'no render path reads ambient state' do
    # Transform::Base#today is the one sanctioned reader: it supplies the
    # default when nothing is injected. Matched as an exact line rather than
    # whitelisting the file, so a second ambient read cannot hide there.
    let(:sanctioned) { '@today ||= Date.today' }
    # Ruby lets whitespace sit either side of a dot or before an argument
    # list, so `Date . today` and `rand (10)` are the same calls. A pattern
    # without \s* passes while they stay on a render path.
    let(:ambient) do
      /\brand\s*\(|\b(?:Date|Time|DateTime)\s*\.\s*(?:today|now)\b/
    end

    it 'calls neither rand nor the clock' do
      offenders = Dir.glob(File.expand_path('../../lib/sirena/**/*.rb', __dir__))
        .flat_map { |file| ambient_reads_in(file) }

      expect(offenders).to be_empty,
                           "ambient state on a render path:\n#{offenders.join("\n")}"
    end

    def ambient_reads_in(file)
      relative = file.sub("#{Dir.pwd}/", '')

      File.readlines(file).each_with_index.filter_map do |line, index|
        # Exact match, not include?. A substring test skipped the whole line,
        # so a second ambient read sharing that line went unreported.
        next if line.strip == sanctioned
        next unless line.match?(ambient)

        "#{relative}:#{index + 1}: #{line.strip}"
      end
    end
  end
end
