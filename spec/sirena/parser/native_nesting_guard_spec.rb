# frozen_string_literal: true

require "open3"
require "rbconfig"
require "spec_helper"

# The native engine recurses on the machine stack once per nested block. A
# source nested past the stack kills the whole process rather than raising,
# so the engine must not be handed one: the Ruby grammar answers instead.
RSpec.describe Sirena::Parser::Native do
  let(:lib_directory) { File.expand_path("../../../lib", __dir__) }

  def nested_flowchart(depth)
    opens = (0...depth).map { |i| "subgraph s#{i}\n" }.join
    "graph TD\n#{opens}A\n#{"end\n" * depth}"
  end

  # Parses on a thread whose stack is 1 MB, the size of a Windows main
  # thread, in a child process so a crash cannot take the suite with it.
  def parse_on_small_stack(source)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{lib_directory.inspect})
      require "sirena"
      Thread.new { Sirena::Parser::Flowchart.new.parse(#{source.inspect}) }.value
      puts "parsed"
    RUBY
    env = { "RUBY_THREAD_MACHINE_STACK_SIZE" => "1048576" }
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script)
    [status.success?, output.lines.last.to_s.strip]
  end

  describe ".parse" do
    it "declines a source nested past the guard" do
      expect(described_class.parse(:flowchart, nested_flowchart(200)))
        .to be_nil
    end

    it "declines deep braces" do
      source = "stateDiagram-v2\n#{"state s {\n" * 40}a --> b\n"

      expect(described_class.parse(:state_diagram, source)).to be_nil
    end

    it "declines deep sequence blocks" do
      source = "sequenceDiagram\n#{"alt x\n" * 40}A->>B: hi\n"

      expect(described_class.parse(:sequence, source)).to be_nil
    end

    it "still answers a source that nests within the guard" do
      skip "parsanol engine unavailable" unless described_class.available?

      expect(described_class.parse(:flowchart, nested_flowchart(8)))
        .not_to be_nil
    end
  end

  # 100 nested subgraphs segfault the engine on a 1 MB stack, while the
  # Ruby grammar parses them there.
  describe "on a small machine stack" do
    it "parses a deeply nested flowchart without killing the process" do
      expect(parse_on_small_stack(nested_flowchart(100)))
        .to eq([true, "parsed"])
    end
  end
end
