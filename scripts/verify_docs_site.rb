# frozen_string_literal: true

# Verifies that docs/_site (Jekyll's build output) actually contains what the
# source config and content claim it should. `jekyll build` exits 0 even when
# a page is missing, mis-themed, unstyled, or references a dead asset -- this
# checks the OUTPUT, not the exit code. See TODO.foundation/15-docs-site-build.md
# and docs/plans/docs-site-build-integrity.md for the full rationale.
#
# Usage: ruby scripts/verify_docs_site.rb [--docs-dir DIR] [--baseurl BASEURL]

require 'yaml'
require 'optparse'
require 'pathname'
require 'strscan'

module Sirena
  # Pure verification core: docs dir + site dir + baseurl in, an array of
  # failure message strings out. No exit, no printing -- see the guarded
  # entry point at the bottom of this file for that.
  class DocsSiteVerifier
    # Asciidoctor::Converter::Html5Converter's block-context handlers, each
    # emitting exactly one of `<context>` or `<context>block` as an HTML
    # class (verified against the real converter -- see the plan's A3
    # section). `table`'s bare form is intentionally absent: Asciidoctor
    # only ever emits `tableblock` for that context.
    BLOCK_MARKERS = %w[
      admonitionblock audioblock colist dlist exampleblock imageblock
      listingblock literalblock olist openblock paragraph quoteblock
      sidebarblock stemblock tableblock ulist verseblock videoblock
    ].freeze

    LAYOUT_BODY_MARKER = 'main-content-wrap'
    SEARCH_INDEX_PATH = 'assets/js/search-data.json'
    REQUIRED_DIAGRAM_PERMALINK = '/:collection/:path/'

    # A minimal but STRUCTURAL HTML tag/attribute tokenizer. Not a DOM
    # parser -- no tree, no nesting -- but it walks each tag's grammar
    # (name, then `name(=value)?` pairs, values quoted or not) with a
    # scanner instead of grepping for a substring, so it cannot mistake
    # text INSIDE an attribute value for another attribute, and it is not
    # sensitive to whitespace around `=`.
    #
    # REXML (stdlib) was tried first and rejected on MEASUREMENT: it is an
    # XML parser, and Jekyll/just-the-docs output is HTML5 with unclosed
    # void elements (`<meta charset="utf-8">`, no self-closing slash),
    # which is invalid XML. `REXML::Document.new` raised
    # `Missing end tag for 'meta'` on 5 of 5 real pages tried -- 100% of
    # the corpus this script exists to check. Pre-cleaning the markup into
    # valid XML before handing it to REXML would need its own regex-based
    # transform, which relocates this defect class rather than removing
    # it. A gem-based HTML5 parser (Nokogiri) would work, but the plan
    # deliberately keeps this script stdlib-only so the CI step needs no
    # `bundle exec` -- pulling in a gem changes that design decision and
    # is bigger than this fix.
    class TagTokenizer
      # `script`/`style`/`textarea` content is raw TEXT per the HTML5 spec
      # -- a literal `<` inside inline JS, CSS or a textarea's placeholder
      # value is not a tag, and none of the three can contain a real
      # nested instance of itself (the first matching close tag always
      # ends it). `template` content IS real markup, but it is INERT: the
      # browser never renders it and JS must clone it in before it counts
      # as part of the page, so a stylesheet link or class living only
      # inside a `<template>` has not actually shipped -- and unlike the
      # raw-text elements, `<template>` genuinely CAN nest as real markup,
      # so skipping it needs to track depth rather than stop at the first
      # close tag, or a `<template><template>...</template>...</template>`
      # would resume tokenizing the outer template's still-inert tail as
      # if it were live.
      RAW_TEXT_ELEMENTS = %w[script style textarea].freeze
      NESTABLE_INERT_ELEMENTS = %w[template].freeze
      SKIPPED_CONTENT_ELEMENTS = (RAW_TEXT_ELEMENTS + NESTABLE_INERT_ELEMENTS).freeze
      TAG_NAME = /[a-zA-Z][\w-]*/
      ATTR_NAME = /[a-zA-Z_:][\w:.-]*/

      # Returns an array of { name:, attrs: } for every tag in `markup`.
      # `attrs` maps a lowercased attribute name to its value (a String),
      # or `true` for a boolean attribute with no value.
      def self.tags(markup)
        new(markup).tags
      end

      def initialize(markup)
        @scanner = StringScanner.new(markup)
        @tags = []
      end

      # `while` on skip_until's own return, not `@scanner.eos?` -- once
      # only closing tags remain, `skip_until(/<(?![!\/])/)` matches
      # nothing FOREVER without moving the scanner, and an `eos?` guard
      # never sees that: it stays false while trailing markup remains
      # unconsumed. Real HTML always ends in closing tags, so this path
      # is not a corner case, it is every real page -- the verifier hung
      # indefinitely on any of them until this was caught by hand.
      def tags
        while @scanner.skip_until(/<(?![!\/])/)
          name = @scanner.scan(TAG_NAME)
          next unless name

          attrs, self_closing = scan_attributes
          @tags << { name: name.downcase, attrs: attrs }
          skip_uninspected_content(name.downcase) unless self_closing
        end
        @tags
      end

      private

      def scan_attributes
        attrs = {}
        loop do
          @scanner.skip(/\s+/)
          return [attrs, false] if @scanner.eos?

          closer = @scanner.scan(%r{/>|>})
          return [attrs, closer == '/>'] if closer

          attr_name = @scanner.scan(ATTR_NAME)
          unless attr_name
            @scanner.getch # malformed input -- advance so this cannot loop forever
            next
          end

          @scanner.skip(/\s*/)
          if @scanner.scan('=')
            @scanner.skip(/\s*/)
            attrs[attr_name.downcase] = scan_attribute_value
          else
            attrs[attr_name.downcase] = true
          end
        end
      end

      def scan_attribute_value
        if @scanner.scan('"')
          @scanner.scan_until(/"/)&.delete_suffix('"').to_s
        elsif @scanner.scan('\'')
          @scanner.scan_until(/'/)&.delete_suffix("'").to_s
        else
          @scanner.scan(/[^\s>]*/).to_s
        end
      end

      # See SKIPPED_CONTENT_ELEMENTS above for why both raw-text and
      # inert elements skip to their close tag unscanned, and why only
      # NESTABLE_INERT_ELEMENTS needs depth tracking to find the RIGHT
      # close tag rather than the first one.
      def skip_uninspected_content(tag_name)
        return unless SKIPPED_CONTENT_ELEMENTS.include?(tag_name)

        if NESTABLE_INERT_ELEMENTS.include?(tag_name)
          skip_nestable_content(tag_name)
        else
          @scanner.scan_until(/<\/#{tag_name}\s*>/i)
        end
      end

      # Tracks nesting depth across every open/close boundary of `tag_name`
      # so a `<template>` inside a `<template>` closes only the inner one.
      # An unterminated tag (malformed input) consumes to end-of-string,
      # matching the raw-text branch's behaviour on the same input.
      def skip_nestable_content(tag_name)
        boundary = /<(\/?)#{tag_name}\b[^>]*>/i
        depth = 1
        while depth.positive?
          return unless @scanner.scan_until(boundary)

          depth += @scanner[1] == '/' ? -1 : 1
        end
      end
    end

    # One page's rendered HTML, read once and queried by every assertion
    # that needs it.
    class Page
      def initialize(path, site_dir)
        @path = path
        @rel_path = Pathname.new(path).relative_path_from(Pathname.new(site_dir)).to_s
      end

      attr_reader :rel_path

      def content
        @content ||= File.read(@path)
      end

      # HTML comments stripped, so markup commented out of the page (a
      # dead stylesheet link, a disabled block) cannot satisfy a check
      # whose whole point is proving the markup is genuinely rendered.
      def markup
        @markup ||= content.gsub(/<!--.*?-->/m, '')
      end

      def tags
        @tags ||= TagTokenizer.tags(markup)
      end

      def class_tokens
        return @class_tokens if @class_tokens

        classes = tags.filter_map { |tag| tag[:attrs]['class'] }.grep(String)
        @class_tokens = classes.flat_map { |value| value.split(/\s+/) }
      end

      def has_class_token?(token)
        class_tokens.include?(token)
      end

      def stylesheet_hrefs
        return @stylesheet_hrefs if @stylesheet_hrefs

        @stylesheet_hrefs = tags.select { |tag| tag[:name] == 'link' && tag[:attrs]['rel'] == 'stylesheet' }
          .filter_map { |tag| tag[:attrs]['href'] }
          .grep(String)
      end

      def script_srcs
        return @script_srcs if @script_srcs

        @script_srcs = tags.select { |tag| tag[:name] == 'script' }
          .filter_map { |tag| tag[:attrs]['src'] }
          .grep(String)
      end
    end

    def initialize(docs_dir:, site_dir:, baseurl: nil)
      @docs_dir = Pathname.new(docs_dir)
      @site_dir = Pathname.new(site_dir)
      @config = YAML.safe_load_file(@docs_dir.join('_config.yml').to_s)
      @baseurl = (baseurl || @config['baseurl']).to_s
    end

    def failures
      config_failures = a0_config_guard
      return config_failures unless config_failures.empty?

      pages = html_pages

      a1_manifest_completeness +
        a2_theme_layout_and_stylesheet(pages) +
        a3_document_content(pages) +
        a4_theme_assets(pages)
    end

    private

    def html_pages
      Dir.glob(@site_dir.join('**/*.html').to_s).map { |path| Page.new(path, @site_dir.to_s) }
    end

    # R1, R2
    def a0_config_guard
      failures = []

      permalink = @config.dig('collections', 'diagram_types', 'permalink')
      if permalink != REQUIRED_DIAGRAM_PERMALINK
        failures << "config: collections.diagram_types.permalink is #{permalink.inspect}, " \
                     "expected #{REQUIRED_DIAGRAM_PERMALINK.inspect}"
      end

      theme = @config['theme']
      failures << 'config: theme is absent or empty' if theme.nil? || theme.to_s.empty?

      failures
    end

    # R3-R7
    def a1_manifest_completeness
      failures = []
      include_active = Array(@config['include']).include?('_diagram_types')

      diagram_sources.each do |rel|
        collection_path = "diagram_types/#{rel}/index.html"
        unless @site_dir.join(collection_path).exist?
          failures << "manifest: _diagram_types/#{rel}.adoc missing at #{collection_path}"
        end

        next unless include_active

        include_path = include_path_for(rel)
        unless @site_dir.join(include_path).exist?
          failures << "manifest: _diagram_types/#{rel}.adoc missing at #{include_path}"
        end
      end

      failures
    end

    def diagram_sources
      diagram_dir = @docs_dir.join('_diagram_types')
      Dir.glob(diagram_dir.join('**/*.adoc').to_s).map do |path|
        Pathname.new(path).relative_path_from(diagram_dir).sub_ext('').to_s
      end
    end

    # Pretty-permalink path for a diagram source, given as its collection-relative
    # path with no extension (e.g. "mindmap", "index", "examples/flowchart-examples").
    # `index` is literal under the collection permalink but collapses under
    # `permalink: pretty`.
    def include_path_for(rel)
      dir = File.dirname(rel)
      base = File.basename(rel)
      if base == 'index'
        dir == '.' ? '_diagram_types/index.html' : "_diagram_types/#{dir}/index.html"
      else
        "_diagram_types/#{rel}/index.html"
      end
    end

    # R8-R11
    def a2_theme_layout_and_stylesheet(pages)
      failures = []
      theme = @config['theme'].to_s

      pages.each do |page|
        unless page.has_class_token?(LAYOUT_BODY_MARKER)
          failures << "layout: #{page.rel_path} missing layout marker #{LAYOUT_BODY_MARKER.inspect}"
        end

        next if page.stylesheet_hrefs.any? { |href| href.include?(theme) }

        failures << "layout: #{page.rel_path} links no stylesheet naming theme #{theme.inspect}"
      end

      failures
    end

    # R12-R16
    def a3_document_content(pages)
      diagram_pages(pages).filter_map do |page|
        next if page.class_tokens.intersect?(BLOCK_MARKERS)

        "content: #{page.rel_path} has no recognized Asciidoctor block marker"
      end
    end

    def diagram_pages(pages)
      pages.select { |page| page.rel_path.start_with?('diagram_types/', '_diagram_types/') }
    end

    # R17-R24
    def a4_theme_assets(pages)
      failures = []
      refs = collect_asset_refs(pages)

      refs.each do |ref, referencing_page|
        next unless site_absolute?(ref)
        next if protocol_relative?(ref)

        resolved = strip_baseurl(ref)
        if resolved.nil?
          failures << "asset: #{ref} (referenced by #{referencing_page}) does not begin with baseurl #{@baseurl.inspect}"
          next
        end

        # Only the path component resolves to a file -- a query string or
        # fragment is not part of the filename a server looks up.
        file_path = resolved.split(/[?#]/, 2).first.to_s
        next if resolves_within_site_dir?(file_path)

        failures << "asset: #{ref} (referenced by #{referencing_page}) does not resolve to #{file_path}"
      end

      if @config['search_enabled'] == true && !@site_dir.join(SEARCH_INDEX_PATH).file?
        failures << "asset: search index #{SEARCH_INDEX_PATH.inspect} missing"
      end

      failures
    end

    # Distinct ref -> first referencing page, so each distinct asset is
    # resolved (and reported) once no matter how many pages link it (R17).
    def collect_asset_refs(pages)
      refs = {}
      pages.each do |page|
        (page.stylesheet_hrefs + page.script_srcs).each do |ref|
          refs[ref] ||= page.rel_path
        end
      end
      refs
    end

    # `../` in a ref can walk the resolved path outside `_site` entirely
    # (e.g. `/sirena/../_config.yml` resolves to a real file one
    # directory up, in `docs/`, not in `docs/_site/`). Cleanpath collapses
    # the traversal, then the result must still sit AT OR UNDER `_site`'s
    # own absolute path before it counts as a resolved asset -- and it
    # must be a regular FILE there. `exist?` is also true for a directory,
    # and a `<link href>` pointing at a directory that happens to share
    # the asset's name is not a stylesheet a server can return.
    def resolves_within_site_dir?(file_path)
      site_root = @site_dir.expand_path
      candidate = site_root.join(file_path.delete_prefix('/')).expand_path

      return false unless candidate.file?

      candidate.to_s.start_with?("#{site_root}/")
    end

    def site_absolute?(ref)
      ref.start_with?('/')
    end

    def protocol_relative?(ref)
      ref.start_with?('//')
    end

    # `nil` means ref does not live under the configured baseurl at all --
    # a real deployment at that baseurl would 404 it, and it is NOT the
    # same thing as a same-named file happening to exist in `_site`'s
    # physical layout (which carries no baseurl prefix directories).
    # Segment-bounded: `/sirenax/...` must not match a `/sirena` baseurl.
    def strip_baseurl(ref)
      return ref if @baseurl.empty?
      return ref[@baseurl.length..] if ref == @baseurl || ref.start_with?("#{@baseurl}/")

      nil
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { docs_dir: 'docs', baseurl: nil }

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby scripts/verify_docs_site.rb [options]'
    opts.on('--docs-dir DIR', 'Path to the docs directory (default: docs)') { |v| options[:docs_dir] = v }
    opts.on('--baseurl BASEURL', 'Baseurl used to resolve site-absolute asset refs') { |v| options[:baseurl] = v }
  end.parse!

  site_dir = File.join(options[:docs_dir], '_site')
  verifier = Sirena::DocsSiteVerifier.new(docs_dir: options[:docs_dir], site_dir: site_dir, baseurl: options[:baseurl])
  failures = verifier.failures

  if failures.empty?
    puts 'docs site verification: OK'
  else
    failures.each { |failure| puts "FAIL: #{failure}" }
    puts "docs site verification: #{failures.size} failure(s)"
  end

  exit(failures.empty? ? 0 : 1)
end
