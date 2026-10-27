# frozen_string_literal: true

require "spec_helper"
require_relative "../support/leptris_fallback_notice_spec_support"

RSpec.describe LeptrisFallbackNoticeSpecSupport do
  let(:notice) do
    "leptris: native acceleration unavailable (leptris: the compiled native " \
      "read layer is not available in this install (leptris: no native_4_0 " \
      "bundle in this install (per-minor native layer; ruby-platform gems " \
      "compile at install)). It ships in pl); using the FFI surface\n"
  end

  it "removes the known startup notice and keeps unrelated stderr" do
    similar_notice = notice.sub("using the FFI surface", "using another")
    stderr = "#{notice}#{similar_notice}unexpected diagnostic\n"
    expected = "#{similar_notice}unexpected diagnostic\n"
    expect(described_class.normalize(stderr)).to eq(expected)
  end
end
