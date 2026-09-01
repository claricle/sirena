# frozen_string_literal: true

require 'tmpdir'

# Interprets mmdc output consistently for every development script that asks
# whether Mermaid accepts a source. Process execution stays with each caller.
module MmdcOracle
  CANARY_SOURCE = "flowchart LR\n  A --> B\n"
  ERROR_ROLE = /\baria-roledescription=(["'])error\1/
  XHTML_STYLE = /<style\b[^>]*\bxmlns=(["'])http:\/\/www\.w3\.org\/1999\/xhtml\1/

  Result = Struct.new(:verdict, :diagnostic)

  module_function

  def verdict(input, &runner)
    Dir.mktmpdir('mmdc-oracle') do |dir|
      probe = run_once(input, File.join(dir, 'probe.svg'), &runner)
      return probe unless probe.verdict == :ambiguous

      canary = run_canary(dir, &runner)
      disambiguate(probe, canary)
    end
  end

  # A syntax failure and the intentional `error` diagram use the same renderer
  # and root role. Measured mmdc output differs at the style element: only the
  # failure page serializes it in the XHTML namespace.
  def error_page?(svg)
    root = svg[/<svg\b[^>]*>/].to_s
    ERROR_ROLE.match?(root) && XHTML_STYLE.match?(svg)
  end

  def run_once(input, output)
    status, diagnostic = yield(input, output)
    Result.new(direct_verdict(status, output), diagnostic.to_s)
  rescue SystemCallError => e
    Result.new(:error, e.message)
  end

  def direct_verdict(status, output)
    return :error if status.nil?
    return :rejects if File.file?(output) && error_page?(File.binread(output))
    return :accepts if successful?(status) && File.file?(output)
    return :error if successful?(status)

    :ambiguous
  end

  def run_canary(dir, &)
    input = File.join(dir, 'canary.mmd')
    File.write(input, CANARY_SOURCE)
    run_once(input, File.join(dir, 'canary.svg'), &)
  end

  def disambiguate(probe, canary)
    return Result.new(:rejects, probe.diagnostic) if canary.verdict == :accepts

    messages = [probe.diagnostic, canary.diagnostic].reject(&:empty?).uniq
    messages << 'mmdc also failed its known-valid health check' if messages.empty?
    Result.new(:error, messages.join("\n"))
  end

  def successful?(status)
    status == true || (status.respond_to?(:success?) && status.success?)
  end
end
