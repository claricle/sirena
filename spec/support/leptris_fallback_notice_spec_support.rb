# frozen_string_literal: true

# leptris emits this one startup notice when its per-Ruby-minor native layer
# is absent. Keep it out of subprocess assertions while preserving all other
# stderr so unexpected diagnostics remain visible.
module LeptrisFallbackNoticeSpecSupport
  NOTICE_TEMPLATE = "leptris: native acceleration unavailable " \
                    "(leptris: the compiled native read layer is not " \
                    "available in this install " \
                    "(leptris: no native_RUBY_VERSION " \
                    "bundle in this install (per-minor native layer; " \
                    "ruby-platform gems compile at install)). It ships in " \
                    "pl); using the FFI surface"
  private_constant :NOTICE_TEMPLATE

  NATIVE_FALLBACK_NOTICE = Regexp.new(
    "\\A#{Regexp.escape(NOTICE_TEMPLATE).sub('RUBY_VERSION', '\\d+_\\d+')}\\n",
  )
  private_constant :NATIVE_FALLBACK_NOTICE

  def self.normalize(text)
    text.gsub(NATIVE_FALLBACK_NOTICE, "")
  end
end
