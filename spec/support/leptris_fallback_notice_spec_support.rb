# frozen_string_literal: true

# Startup notices from dependencies that child Ruby processes inherit.
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

  # lutaml-model prints this once per process when yeptris is in the bundle
  # but LUTAML_YAML=yeptris is not set. It has no silencing switch: the only
  # env var opts in to the native engine, which would change what the child
  # processes exercise. It is stripped on its own line, wherever it falls.
  YEPTRIS_NOT_ENABLED_NOTICE = Regexp.new(
    "^\\[Lutaml::Model\\] yeptris is present in this bundle but the native " \
    "YAML engine is not enabled[^\\n]*\\n",
  )
  private_constant :YEPTRIS_NOT_ENABLED_NOTICE

  def self.normalize(text)
    text.gsub(YEPTRIS_NOT_ENABLED_NOTICE, "").gsub(NATIVE_FALLBACK_NOTICE, "")
  end
end
