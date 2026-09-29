# frozen_string_literal: true

require "spec_helper"
require "open3"
require "sirena/parser/git_graph"

module GitGraphScalingHelpers
  def min_call_time(attempts: 3, &block)
    Array.new(attempts) { average_call_time(&block) }.min
  end

  def average_call_time
    total = 0.0
    calls = 0
    while total < 0.05
      total += yield
      calls += 1
      break if calls >= 20_000
    end
    total / calls
  end

  # Process.times, not clock_gettime: Windows Ruby has no CPU-time clock
  # for clock_gettime and raises Errno::EINVAL.
  def cpu_time
    start = Process.times
    yield
    finish = Process.times
    (finish.utime + finish.stime) - (start.utime + start.stime)
  end

  # A full gitGraph diagram with `count` sequential branches, each with
  # its own short name -- stresses `TrimmedRun`/`GreedyRun` called once
  # PER BRANCH, the shape a fixed-size chunk regresses on (many short
  # calls, not one long run).
  def many_branches_source(count)
    branches = Array.new(count) { |i| "  branch b#{i}" }.join("\n")
    "gitGraph\n#{branches}\n"
  end
end

RSpec.describe Sirena::Parser::GitGraph do
  include GitGraphScalingHelpers

  let(:parser) { described_class.new }

  describe "#parse" do
    context "with simple commits" do
      it "parses a single commit" do
        source = <<~MERMAID
          gitGraph
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::GitGraph)
        expect(diagram.commits.size).to eq(1)
        expect(diagram.commits.first.branch_name).to eq("main")
      end

      it "parses multiple commits with IDs" do
        source = <<~MERMAID
          gitGraph
            commit id: "One"
            commit id: "Two"
            commit id: "Three"
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.commits.size).to eq(3)
        expect(diagram.commits.map(&:id)).to eq(["One", "Two", "Three"])
      end

      it "parses commits with types" do
        source = <<~MERMAID
          gitGraph
            commit type: NORMAL
            commit type: REVERSE
            commit type: HIGHLIGHT
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.commits.size).to eq(3)
        expect(diagram.commits.map(&:type)).to eq(
          ["NORMAL", "REVERSE", "HIGHLIGHT"]
        )
      end

      it "parses commits with tags" do
        source = <<~MERMAID
          gitGraph
            commit tag: "v1.0"
            commit id: "Two" tag: "v2.0"
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.commits.size).to eq(2)
        expect(diagram.commits.map(&:tag)).to eq(["v1.0", "v2.0"])
      end
    end

    context "with branches" do
      it "parses branch creation" do
        source = <<~MERMAID
          gitGraph
            commit
            branch develop
            checkout develop
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.branches.size).to eq(2) # main and develop
        expect(diagram.branches.map(&:name)).to include("develop")
        expect(diagram.commits.size).to eq(2)
        expect(diagram.commits.last.branch_name).to eq("develop")
      end

      # mermaid accepts real git branch names, not just identifiers.
      # Corpus case unknown/013_platform_gitgraph_12.mmd checks out
      # "release/1.0.0".
      it "parses a branch name with a slash and dots" do
        source = <<~MERMAID
          gitGraph
            commit
            branch release/1.0.0
            checkout release/1.0.0
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.branches.map(&:name)).to include("release/1.0.0")
        expect(diagram.commits.last.branch_name).to eq("release/1.0.0")
      end

      # mermaid's own `REFERENCE` token (`/\w([-.\/\w]*[-\w])?/`) requires
      # a word character first and a word character or hyphen last --
      # `.` and `/` are only legal in the middle. A Codex review found an
      # earlier version of `branch_name` accepted all four leading/trailing
      # forms mermaid rejects.
      it "rejects a branch name starting or ending with a dot or slash" do
        grammar = Sirena::Parser::Grammars::GitGraph.new

        # Proves the rejections below are about the boundary specifically,
        # not dots/slashes being unsupported entirely -- the old character
        # class (`[a-zA-Z0-9_-]`) rejected a dot or slash ANYWHERE, so
        # without this the raise_error expectations below would pass for
        # the wrong reason on that old, narrower class.
        expect(grammar.branch_name.parse("release/1.0.0").to_s)
          .to eq("release/1.0.0")

        %w[.foo /foo foo. foo/].each do |name|
          expect { grammar.branch_name.parse(name) }
            .to raise_error(Parslet::ParseFailed), "expected #{name.inspect} to be rejected"
        end
      end

      # A CHUNK-BOUNDARY regression: `branch_name`'s greedy tail run is
      # matched internally in bounded chunks (`TrimmedRun`, see the
      # grammar comment) -- a naive per-chunk anchored regex is only
      # exact for a pure character-class run, not this pattern's
      # trailing-anchor requirement (must end in `-`/word, not `.`/`/`),
      # so a name straddling the chunk boundary used to truncate at the
      # boundary instead of continuing into the next chunk. Compared
      # against the SAME regex mermaid's own REFERENCE token uses, run on
      # the whole string at once, not hand-derived.
      it "matches a branch name whose greedy tail run crosses the internal chunk boundary" do
        grammar = Sirena::Parser::Grammars::GitGraph.new
        whole_input_regex = Regexp.new('\A(?:\w([-.\/\w]*[-\w])?)', Regexp::MULTILINE)

        [
          "#{'a' * 49_999}.#{'b' * 10}",
          "#{'a' * 50_000}.b"
        ].each do |name|
          expected = whole_input_regex.match(name)[0]
          expect(grammar.branch_name.parse(name, prefix: true).to_s).to eq(expected)
        end
      end

      # `branch_name` is `match['\w'] >> TrimmedRun.new(...)` -- the
      # leading `match['\w']` consumes ONE character before `TrimmedRun`'s
      # own run starts, so the run itself starts at position 1, not 0.
      # `50_000` (not `49_999`) `a`s here puts the `.` as the LAST
      # character of the run's first internal chunk.
      it "parses a full branch statement whose name crosses the internal chunk boundary" do
        name = "#{'a' * 50_000}.bbbbbbbbbb"
        source = <<~MERMAID
          gitGraph
            branch #{name}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.branches.map(&:name)).to include(name)
      end

      # Differential check against the SAME whole-input regex used above,
      # across random tail content and lengths clustered around the
      # internal chunk boundary (plus a spread of other sizes) -- proves
      # the chunk-boundary fix generalises past the two hand-picked
      # counterexamples the regression report named.
      it "matches the whole-input reference regex across random inputs near the chunk boundary" do
        grammar = Sirena::Parser::Grammars::GitGraph.new
        whole_input_regex = Regexp.new('\A(?:\w([-.\/\w]*[-\w])?)', Regexp::MULTILINE)
        broad_pool = ("a".."z").to_a + ("0".."9").to_a + ["-", ".", "/", "_"]
        noise_pool = [" ", "!"]
        rng = Random.new(20_260_929)
        lengths = Array.new(40) { rng.rand(1..20) } +
                  Array.new(40) { rng.rand(49_990..50_010) } +
                  Array.new(20) { rng.rand(1..150_000) } +
                  [64, 128, 256, 512, 1_024, 2_048, 4_096, 8_192, 16_384, 32_768, 50_000]

        mismatches = lengths.filter_map do |length|
          tail = Array.new(length) { rng.rand(20) < 19 ? broad_pool.sample(random: rng) : noise_pool.sample(random: rng) }.join
          input = "a#{tail}"
          expected = whole_input_regex.match(input)[0]
          got = grammar.branch_name.parse(input, prefix: true).to_s
          { length: length, expected: expected.length, got: got.length } if got != expected
        end

        expect(mismatches).to eq([]), "#{mismatches.size}/#{lengths.size} cases mismatched: #{mismatches.first(3)}"
      end

      # Guards against the OTHER shape a fixed-size-chunk atom can
      # regress on: many SHORT branch names, not one long one.
      # `branch_name`'s run used to chunk at a fixed 50_000-char ceiling
      # regardless of the run's own length, so every short branch name
      # still paid a ~50_000-char consume + rewind per statement --
      # linear in the chunk size per branch, not in the name's own
      # length. Scaling ratio, not an absolute bound, for the same
      # reason as spec/support/er_tilde_timing.rb.
      it "parses many branches with short names at a linear rate, not one per fixed chunk" do
        small_time = min_call_time { cpu_time { parser.parse(many_branches_source(500)) } }
        large_time = min_call_time { cpu_time { parser.parse(many_branches_source(4_000)) } }

        expect(large_time / small_time).to be < 30
      end

      it "parses branch with order" do
        source = <<~MERMAID
          gitGraph
            commit
            branch test1 order: 3
            branch test2 order: 2
        MERMAID

        diagram = parser.parse(source)
        branch1 = diagram.branches.find { |b| b.name == "test1" }
        branch2 = diagram.branches.find { |b| b.name == "test2" }
        expect(branch1.order).to eq(3)
        expect(branch2.order).to eq(2)
      end

      it "parses switch statement" do
        source = <<~MERMAID
          gitGraph
            commit
            branch testBranch
            switch testBranch
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.commits.last.branch_name).to eq("testBranch")
      end
    end

    context "with merges" do
      it "parses merge operations" do
        source = <<~MERMAID
          gitGraph
            commit
            branch develop
            checkout develop
            commit id: "Feature"
            checkout main
            merge develop
        MERMAID

        diagram = parser.parse(source)
        merge_commit = diagram.commits.last
        expect(merge_commit.is_merge).to be true
        expect(merge_commit.merge_branch).to eq("develop")
      end

      it "parses merge with id and tag" do
        source = <<~MERMAID
          gitGraph
            commit
            branch develop
            checkout develop
            commit
            checkout main
            merge develop id: "M1" tag: "v1.0"
        MERMAID

        diagram = parser.parse(source)
        merge_commit = diagram.commits.last
        expect(merge_commit.id).to eq("M1")
        expect(merge_commit.tag).to eq("v1.0")
        expect(merge_commit.is_merge).to be true
      end
    end

    context "with cherry-picks" do
      it "parses cherry-pick operations" do
        source = <<~MERMAID
          gitGraph
            commit id: "A"
            branch feature
            checkout feature
            commit id: "B"
            checkout main
            cherry-pick id: "B"
        MERMAID

        diagram = parser.parse(source)
        cp_commit = diagram.commits.last
        expect(cp_commit.is_cherry_pick).to be true
      end

      it "parses cherry-pick with parent and tag" do
        source = <<~MERMAID
          gitGraph
            commit id: "ZERO"
            branch feature
            checkout feature
            commit id: "A"
            checkout main
            cherry-pick id: "A" parent: "ZERO" tag: "v1.0"
        MERMAID

        diagram = parser.parse(source)
        cp_commit = diagram.commits.last
        expect(cp_commit.is_cherry_pick).to be true
        expect(cp_commit.cherry_pick_parent).to eq("ZERO")
        expect(cp_commit.tag).to eq("v1.0")
      end
    end

    context "with orientation" do
      it "parses TB orientation" do
        source = <<~MERMAID
          gitGraph TB:
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::GitGraph)
        expect(diagram.commits.size).to eq(1)
      end

      it "parses LR orientation" do
        source = <<~MERMAID
          gitGraph LR:
            commit
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::GitGraph)
        expect(diagram.commits.size).to eq(1)
      end
    end
  end

  # `branch_name`'s `GreedyRun` (via `TrimmedRun`) used to resolve only
  # through a private constant that `grammars/er_diagram.rb` happened to
  # define -- so requiring `sirena/parser/grammars/git_graph` alone,
  # without the ER grammar loaded first, raised `NameError: uninitialized
  # constant ...GitGraph::GreedyRun`. In-process this is silently masked once
  # spec_helper has loaded the whole gem ($LOADED_FEATURES makes a
  # second `require` a no-op), so this shells out to a real subprocess.
  describe "grammar file, required standalone" do
    it "loads sirena/parser/grammars/git_graph and parses a branch name without the ER grammar loaded first" do
      out, status = Open3.capture2e(
        "ruby", "-Ilib", "-e",
        'require "sirena/parser/grammars/git_graph"; ' \
        'tree = Sirena::Parser::Grammars::GitGraph.new.parse("gitGraph\n  branch release/1.0\n"); ' \
        'puts tree[:statements].first[:branch][:name]'
      )

      expect(status).to be_success, "expected exit 0, got #{status.exitstatus}:\n#{out}"
      expect(out.strip).to eq("release/1.0")
    end
  end
end