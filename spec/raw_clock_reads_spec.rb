# frozen_string_literal: true

require "tempfile"

RSpec.describe RawClockReads do
  {
    "Process.clock_gettime(Process::CLOCK_MONOTONIC)" => [1],
    "Process\n  .clock_gettime(Process::CLOCK_MONOTONIC)" => [1],
    "Process::times" => [1],
    "::Benchmark.realtime { 1 }" => [1],
    "Benchmark.measure { 1 }" => [1],
    "Benchmark.benchmark(\"x\") { 1 }" => [1],
    "Object::Process.times" => [1],
    "::Object::Process.times" => [1],
    "Kernel::Process.times" => [],
    "Foo::Object::Process.times" => [],
    "Foo::Process.times" => [],
    "Process::Status.times" => [],
    "def t\n  Benchmark.bmbm { 1 }\nend" => [2],
    "# Process.times" => [],
    "\"Process.times\"" => [],
    "3.times { 1 }" => [],
    "Benchmark.new" => [],
    "value.parse(1)" => [],
    "parse(1)" => [],
  }.each do |source, lines|
    it "finds raw reads on lines #{lines} of #{source.inspect}" do
      expect(described_class.lines(source)).to eq(lines)
    end
  end

  it "refuses source that does not parse" do
    expect { described_class.lines("Process.times(") }
      .to raise_error(ArgumentError, /does not parse/)
  end

  # The scanner's answer for `defined?(operand)` is pinned to what Ruby does:
  # each operand runs against a `Process.times` that counts its calls.
  describe "operands of defined?" do
    let(:reads) { [] }
    let(:host) do
      Class.new do
        def foo(*) = self
        def foo=(_value); end
        def bar = self
        def [](*) = self
        def []=(*); end
      end.new
    end

    before do
      counted = reads
      allow(Process).to receive(:times) do
        counted << :read
        host
      end
    end

    [
      "Process.times",
      "Process.times.foo",
      "Process.times.foo(1)",
      "Process.foo(Process.times)",
      "Process.times&.foo",
      "Process.times[1]",
      "Process.times.foo = 1",
      "Process.times[1] = 2",
      "Process.times.foo += 1",
      "Process.times.foo ||= 1",
      "Process.times.foo &&= 1",
      "Process.times[1] += 1",
      "Process.times && 1",
      "Process.times || 1",
      "x = Process.times",
      "!Process.times",
      "Process.times::Bar",
      "Process.times.foo::Bar",
      "[Process.times]",
      "[Process.times.bar]",
      "{ a: Process.times.bar }",
      "1 + Process.times.bar",
      "(Process.times)",
      "(Process.times.bar)",
      "(1; Process.times.bar)",
      "foo(Process.times)",
      "foo(Process.times.bar)",
      "foo(a: Process.times.bar)",
      "foo(*Process.times.bar)",
      "foo(**Process.times.bar)",
      "foo(&Process.times.bar)",
      "foo(Process.times.bar) { 1 }",
      "Process.times.foo { 1 }",
      "Process.times.bar ? 1 : 2",
      "if 1 then Process.times.bar end",
      "\"\#{Process.times.bar}\"",
      "Process.times.bar..1",
      "not Process.times.bar",
      "::Process.times.bar",
      "Process.times[Process.times.bar]",
    ].each do |operand|
      it "agrees with Ruby on defined?(#{operand})" do
        source = "defined?(#{operand})"
        host.instance_eval(source, __FILE__, __LINE__)
        expect(described_class.lines(source).any?).to eq(reads.any?)
      end
    end
  end

  describe ".find" do
    let(:file) { Tempfile.new(["clock", ".rb"]) }
    let(:path) { file.path }

    before do
      file.write(source)
      file.flush
    end

    after { file.close! }

    context "with a read on line 2" do
      let(:source) { "x = 1\nProcess.times\n" }

      it "names the file and line of each read it finds" do
        expect(described_class.find(path)).to eq(["#{path}:2"])
      end
    end

    context "with source that does not parse" do
      let(:source) { "def (" }

      it "names the file in the error" do
        expect { described_class.find(path) }
          .to raise_error(ArgumentError, /#{Regexp.escape(path)}/)
      end
    end
  end
end
