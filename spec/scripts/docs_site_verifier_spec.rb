# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'timeout'
require_relative '../../scripts/verify_docs_site'

# Defined outside the RSpec.describe block deliberately: RuboCop's
# Lint/ConstantDefinitionInBlock autocorrect turns a block-level constant
# into a block-LOCAL variable, and dev.md documents that autocorrect
# silently making a later example's own assignment shadow the "constant"
# instead of raising. Keeping these at file scope avoids the hazard rather
# than relying on nobody running `rubocop -a` on this file later.
DOCS_SITE_VERIFIER_DEFAULT_THEME = 'just-the-docs'
DOCS_SITE_VERIFIER_DEFAULT_BASEURL = '/sirena'

RSpec.describe Sirena::DocsSiteVerifier do
  # -- fixture builders -------------------------------------------------
  # `def`s, not `let`s: every one takes arguments (rspec.rubystyle.guide has
  # no rule against this; `let` has no arity, see dev.md's RSpec `let` note).

  def write_config(docs_dir, overrides = {})
    config = {
      'theme' => DOCS_SITE_VERIFIER_DEFAULT_THEME,
      'baseurl' => DOCS_SITE_VERIFIER_DEFAULT_BASEURL,
      'search_enabled' => true,
      'include' => ['_diagram_types'],
      'collections' => {
        'diagram_types' => { 'permalink' => '/:collection/:path/' },
      },
    }.merge(overrides)
    File.write(File.join(docs_dir, '_config.yml'), YAML.dump(config))
  end

  def write_source(docs_dir, relative)
    path = File.join(docs_dir, '_diagram_types', "#{relative}.adoc")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "= #{File.basename(relative)}\n\nplaceholder\n")
  end

  def write_page(site_dir, relative_html_path, html)
    path = File.join(site_dir, relative_html_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, html)
  end

  def write_asset(site_dir, relative_path, content = '/* asset */')
    path = File.join(site_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  # A fully valid rendered page: theme stylesheet + layout marker + a
  # recognized Asciidoctor block marker. Every knob defaults to the
  # correct value so a test overriding exactly one produces exactly one
  # failure.
  def page_html(theme: DOCS_SITE_VERIFIER_DEFAULT_THEME, baseurl: DOCS_SITE_VERIFIER_DEFAULT_BASEURL,
                 marker: 'paragraph', layout_marker: 'main-content-wrap', stylesheet: true, extra: {})
    stylesheet_tag = stylesheet ? %(<link rel="stylesheet" href="#{baseurl}/assets/css/#{theme}-default.css">) : ''
    script_tag = extra[:script] ? %(<script src="#{extra[:script]}"></script>) : ''
    link_tag = extra[:link] ? %(<link rel="#{extra[:link][:rel]}" href="#{extra[:link][:href]}">) : ''
    anchor_tag = extra[:dangling_anchor] ? %(<a href="#{baseurl}/does-not-exist-anywhere">x</a>) : ''
    <<~HTML
      <html><head>#{stylesheet_tag}#{link_tag}</head>
      <body>
        <div class="#{layout_marker}">
          #{script_tag}
          <div class="#{marker}"><p>hi</p></div>
          #{anchor_tag}
        </div>
      </body></html>
    HTML
  end

  # Builds a docs_dir/site_dir pair with one diagram source ("mindmap")
  # rendered, correctly, at both the collection path and the include path,
  # plus the theme asset it references. Every other example starts from
  # this and breaks exactly one thing.
  def build_valid_site(tmp, config_overrides: {})
    docs_dir = File.join(tmp, 'docs')
    site_dir = File.join(docs_dir, '_site')
    FileUtils.mkdir_p(docs_dir)

    write_config(docs_dir, config_overrides)
    write_source(docs_dir, 'mindmap')
    write_page(site_dir, 'diagram_types/mindmap/index.html', page_html)
    write_page(site_dir, '_diagram_types/mindmap/index.html', page_html)
    write_asset(site_dir, "assets/css/#{DOCS_SITE_VERIFIER_DEFAULT_THEME}-default.css")
    write_asset(site_dir, 'assets/js/search-data.json')

    [docs_dir, site_dir]
  end

  def verifier_for(docs_dir, site_dir, baseurl: nil)
    described_class.new(docs_dir: docs_dir, site_dir: site_dir, baseurl: baseurl)
  end

  # ----------------------------------------------------------------------
  # Example 1 — green control. Also, per the plan, the dangling
  # site-absolute <a href> doubles as R23's detector: if the verifier ever
  # started collecting anchor refs, this example alone would catch it.
  it 'reports no failures for a complete site, and does not collect a dangling <a href>' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html(extra: { dangling_anchor: true }))
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html(extra: { dangling_anchor: true }))

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 2 — R3
  it 'names the source and path when the collection-path page is absent' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      FileUtils.rm_rf(File.join(site_dir, 'diagram_types'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'manifest: _diagram_types/mindmap.adoc missing at diagram_types/mindmap/index.html'
      )
    end
  end

  # Example 3 — R4
  it 'names the source and path when the include-path page is absent and include: names _diagram_types' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      FileUtils.rm_rf(File.join(site_dir, '_diagram_types'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'manifest: _diagram_types/mindmap.adoc missing at _diagram_types/mindmap/index.html'
      )
    end
  end

  # Example 4 — R5
  it 'reports no failures when include: omits _diagram_types and _site has no include-path copy' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp, config_overrides: { 'include' => [] })
      FileUtils.rm_rf(File.join(site_dir, '_diagram_types'))

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 5 — R6
  it 'requires a nested source at both nested paths' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_source(docs_dir, 'examples/flowchart-examples')
      write_page(site_dir, 'diagram_types/examples/flowchart-examples/index.html', page_html)
      write_page(site_dir, '_diagram_types/examples/flowchart-examples/index.html', page_html)
      FileUtils.rm_rf(File.join(site_dir, 'diagram_types/examples'))
      FileUtils.rm_rf(File.join(site_dir, '_diagram_types/examples'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'manifest: _diagram_types/examples/flowchart-examples.adoc missing at ' \
          'diagram_types/examples/flowchart-examples/index.html',
        'manifest: _diagram_types/examples/flowchart-examples.adoc missing at ' \
          '_diagram_types/examples/flowchart-examples/index.html'
      )
    end
  end

  # Example 6 — R7
  it 'requires index.adoc at diagram_types/index/index.html and _diagram_types/index.html' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_source(docs_dir, 'index')
      write_page(site_dir, 'diagram_types/index/index.html', page_html)
      write_page(site_dir, '_diagram_types/index.html', page_html)
      FileUtils.rm_rf(File.join(site_dir, 'diagram_types/index'))
      FileUtils.rm(File.join(site_dir, '_diagram_types/index.html'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'manifest: _diagram_types/index.adoc missing at diagram_types/index/index.html',
        'manifest: _diagram_types/index.adoc missing at _diagram_types/index.html'
      )
    end
  end

  # Example 6b — R7, NESTED index. Example 6 only exercises the top-level
  # `dir == '.'` arm; a mutant that collapsed every index source to the
  # same top-level `_diagram_types/index.html` survived every other
  # example because none of them nested an index.adoc in a subdirectory.
  it 'collapses a nested index.adoc to its own subdirectory, not the site root' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_source(docs_dir, 'examples/index')
      write_page(site_dir, 'diagram_types/examples/index/index.html', page_html)
      write_page(site_dir, '_diagram_types/examples/index.html', page_html)
      FileUtils.rm_rf(File.join(site_dir, 'diagram_types/examples/index'))
      FileUtils.rm(File.join(site_dir, '_diagram_types/examples/index.html'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'manifest: _diagram_types/examples/index.adoc missing at diagram_types/examples/index/index.html',
        'manifest: _diagram_types/examples/index.adoc missing at _diagram_types/examples/index.html'
      )
    end
  end

  # Example 7 — R8. Strip the layout marker while keeping the stylesheet
  # links, proving R8 is not a duplicate of R9.
  it 'names the page lacking the layout marker while its theme stylesheet stays intact' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html(layout_marker: 'main-content-wrapX'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'layout: diagram_types/mindmap/index.html missing layout marker "main-content-wrap"'
      )
    end
  end

  # Example 8 — R9. Strip the stylesheet while keeping the layout marker
  # and a theme-named <script src>, so an implementation reading R9 as
  # "any ref containing the theme name" is defeated.
  it 'names the page linking no theme stylesheet while the layout marker and a theme-named script stay' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(
        site_dir, 'diagram_types/mindmap/index.html',
        page_html(stylesheet: false, extra: { script: "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/js/#{DOCS_SITE_VERIFIER_DEFAULT_THEME}.js" })
      )
      write_asset(site_dir, "assets/js/#{DOCS_SITE_VERIFIER_DEFAULT_THEME}.js")

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        "layout: diagram_types/mindmap/index.html links no stylesheet naming theme #{DOCS_SITE_VERIFIER_DEFAULT_THEME.inspect}"
      )
    end
  end

  # Example 9 — R10. theme: is "pico" while the page links just-the-docs
  # CSS, so a hardcoded "just-the-docs" string cannot pass by accident.
  it 'reports a page linking only just-the-docs CSS when theme: is pico' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp, config_overrides: { 'theme' => 'pico' })

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'layout: diagram_types/mindmap/index.html links no stylesheet naming theme "pico"',
        'layout: _diagram_types/mindmap/index.html links no stylesheet naming theme "pico"'
      )
    end
  end

  # Example 10 — R11. A2 is site-wide: a non-diagram page missing the
  # stylesheet is reported too.
  it 'reports a non-diagram page missing the theme stylesheet' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'pages/comparison/index.html', page_html(stylesheet: false))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'layout: pages/comparison/index.html links no stylesheet naming theme "just-the-docs"'
      )
    end
  end

  # Example 10b — R11, the layout-marker half. A2 has two site-wide
  # clauses (layout marker, stylesheet); example 10 above only pins the
  # stylesheet one. A mutant that scopes the LAYOUT check to diagram pages
  # only survived every example until this was added.
  it 'reports a non-diagram page missing the layout marker' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'pages/comparison/index.html', page_html(layout_marker: 'main-content-wrapX'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'layout: pages/comparison/index.html missing layout marker "main-content-wrap"'
      )
    end
  end

  # Example 11 — R12
  it 'names the diagram page carrying no recognized block marker' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html(marker: 'not-a-real-marker'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # Example 12 — R13. Four pages, each a shape a hand-picked marker set
  # got wrong in an earlier revision: table-only, list-only, listing-only
  # and image-only (examples.rake's default-metadata output, split so
  # neither masks the other -- see the note on the LOW finding below).
  # None exists in today's real _site.
  it 'passes a table-only page, a list-only page, a listing-only page and an image-only page' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      %w[table-page list-page listing-page image-page].each { |name| write_source(docs_dir, name) }

      bodies = {
        'table-page' => '<table class="tableblock"><tr><td>x</td></tr></table>',
        'list-page' => '<ul class="ulist"><li>x</li></ul>',
        'listing-page' => '<div class="listingblock">x</div>',
        'image-page' => '<div class="imageblock">x</div>',
      }
      bodies.each do |name, body|
        write_page(site_dir, "diagram_types/#{name}/index.html", page_html_with_body(body))
        write_page(site_dir, "_diagram_types/#{name}/index.html", page_html_with_body(body))
      end

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 12b — R13, negative direction. Codex found `table` (the bare
  # context, not `tableblock`) sitting in BLOCK_MARKERS, contradicting this
  # file's own comment that Asciidoctor never emits it bare. A page whose
  # only class is literally "table" must still be reported.
  it 'does not accept bare "table" as a recognized block marker' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html(marker: 'table'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # Example 12c — R13, the LOW Codex found: deleting `imageblock` from
  # BLOCK_MARKERS left every example green because the one page exercising
  # it also carried `listingblock`. Example 12 above now keeps the two
  # markers on SEPARATE pages, so each is independently load-bearing; this
  # example pins that directly by deleting the marker from a page's own
  # class list and expecting a failure.
  it 'reports an image-only page whose sole marker class is missing' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_source(docs_dir, 'image-only')
      body = '<div class="not-a-real-marker">x</div>'
      write_page(site_dir, 'diagram_types/image-only/index.html', page_html_with_body(body))
      write_page(site_dir, '_diagram_types/image-only/index.html', page_html_with_body(body))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/image-only/index.html has no recognized Asciidoctor block marker',
        'content: _diagram_types/image-only/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # Example 13 — R14, lead-role form only.
  it 'accepts a page whose only marked div is class="paragraph lead"' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      body = '<div class="paragraph lead"><p>hi</p></div>'
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html_with_body(body))
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html_with_body(body))

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 14 — R14, anchored form only.
  it 'accepts a page whose only marked div is <div id="..." class="paragraph">' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      body = '<div id="example-metadata" class="paragraph"><p>hi</p></div>'
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html_with_body(body))
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html_with_body(body))

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 15 — R15
  it 'reports a page in the underscore tree missing every marker' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html(marker: 'not-a-real-marker'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: _diagram_types/mindmap/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # Example 16 — R16
  it 'does not report a non-diagram page missing every marker' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'pages/comparison/index.html', page_html(marker: 'not-a-real-marker'))

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 17 — R17, "collected from every page". The unique missing
  # asset sits on the page that sorts LAST under Dir.glob's sorted order,
  # so a first-page-only implementation would miss it.
  it 'reports a unique missing asset referenced only by the last-traversed non-diagram page' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      # 'pages/zzz-last' sorts after 'diagram_types/...' and '_diagram_types/...'
      write_page(
        site_dir, 'pages/zzz-last/index.html',
        page_html(extra: { script: "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/js/only-here.js" })
      )

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        "asset: #{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/js/only-here.js (referenced by pages/zzz-last/index.html) " \
          'does not resolve to /assets/js/only-here.js'
      )
    end
  end

  # Example 18 — R17, "resolved once". Three pages share one missing
  # asset; it must be reported exactly once.
  it 'reports one missing asset referenced by three pages exactly once' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      missing_script = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/js/shared-missing.js"
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html(extra: { script: missing_script }))
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html(extra: { script: missing_script }))
      write_page(site_dir, 'pages/other/index.html', page_html(extra: { script: missing_script }))

      expect(verifier_for(docs_dir, site_dir).failures.length).to eq(1)
      expect(verifier_for(docs_dir, site_dir).failures.first).to include('shared-missing.js')
    end
  end

  # Example 19 — R18. A supplied baseurl different from the config's is
  # what gets stripped.
  it 'strips the supplied --baseurl, not the config baseurl, when resolving refs' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html(baseurl: '/other-base'))
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html(baseurl: '/other-base'))
      write_asset(site_dir, 'assets/css/just-the-docs-default.css')

      failures = verifier_for(docs_dir, site_dir, baseurl: '/other-base').failures
      expect(failures).to eq([])
    end
  end

  # Example 20 — R19
  it 'reports a missing asset referenced only by a link[rel=stylesheet]' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(
        site_dir, 'diagram_types/mindmap/index.html',
        page_html(extra: { link: { rel: 'stylesheet', href: "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/css/missing.css" } })
      )

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        "asset: #{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/css/missing.css (referenced by diagram_types/mindmap/index.html) " \
          'does not resolve to /assets/css/missing.css'
      )
    end
  end

  # Example 21 — R20
  it 'reports a missing asset referenced only by a script[src]' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(
        site_dir, 'diagram_types/mindmap/index.html',
        page_html(extra: { script: "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/js/missing.js" })
      )

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        "asset: #{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/js/missing.js (referenced by diagram_types/mindmap/index.html) " \
          'does not resolve to /assets/js/missing.js'
      )
    end
  end

  # Example 22 — R21, external
  it 'does not report an external https stylesheet as missing' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(
        site_dir, 'diagram_types/mindmap/index.html',
        page_html(extra: { link: { rel: 'stylesheet', href: 'https://fonts.googleapis.com/x.css' } })
      )
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html)

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 23 — R21, relative
  it 'does not report a relative stylesheet as missing' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(
        site_dir, 'diagram_types/mindmap/index.html',
        page_html(extra: { link: { rel: 'stylesheet', href: 'assets/css/relative.css' } })
      )
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html)

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 24 — R22
  it 'does not report a protocol-relative stylesheet as missing' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(
        site_dir, 'diagram_types/mindmap/index.html',
        page_html(extra: { link: { rel: 'stylesheet', href: '//cdn.example.com/x.css' } })
      )
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html)

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 25 — R23, anchor
  it 'does not report a dangling site-absolute <a href> as a missing asset' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html(extra: { dangling_anchor: true }))
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html)

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 26 — R23, non-stylesheet <link>. Site-absolute, unlike a real
  # canonical link, so the site-absolute filter cannot mask this the way
  # it masks real rel="canonical" hrefs.
  it 'does not report a dangling site-absolute link[rel=preload] as a missing asset' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_page(
        site_dir, 'diagram_types/mindmap/index.html',
        page_html(extra: { link: { rel: 'preload', href: "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/does-not-exist.woff2" } })
      )
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html)

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 27 — R24
  it 'requires the search index when search_enabled is true, and not when false' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      FileUtils.rm(File.join(site_dir, 'assets/js/search-data.json'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'asset: search index "assets/js/search-data.json" missing'
      )

      docs_dir2, site_dir2 = build_valid_site(File.join(tmp, 'no-search'), config_overrides: { 'search_enabled' => false })
      FileUtils.rm(File.join(site_dir2, 'assets/js/search-data.json'))

      expect(verifier_for(docs_dir2, site_dir2).failures).to eq([])
    end
  end

  # Example 28 — R1
  it 'refuses, naming the template found, when the collection permalink differs' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(
        tmp, config_overrides: { 'collections' => { 'diagram_types' => { 'permalink' => '/:path/' } } }
      )

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'config: collections.diagram_types.permalink is "/:path/", expected "/:collection/:path/"'
      )
    end
  end

  # Example 29 — R2, empty string.
  it 'refuses when theme: is empty' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp, config_overrides: { 'theme' => '' })

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'config: theme is absent or empty'
      )
    end
  end

  # Example 29b — R2, key genuinely ABSENT (nil), not merely an empty
  # string. `theme.nil? || theme.to_s.empty?` collapses to `theme == ''`
  # and stays true for '' -- but a config with no `theme:` key at all
  # (Psych parses that as nil) is only caught by the `.nil?` half.
  it 'refuses when theme: is not set at all' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp, config_overrides: { 'theme' => nil })

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'config: theme is absent or empty'
      )
    end
  end

  # ----------------------------------------------------------------------
  # The five findings from the first Codex round on this file. Each is a
  # constructed input Codex ran against the real implementation; every one
  # is reproduced here as its own example so it cannot regress silently.

  # HIGH-1a. A commented-out stylesheet link must not satisfy A2's
  # stylesheet clause -- text-matching without stripping comments made a
  # dead link indistinguishable from a live one.
  it 'reports a page whose only theme stylesheet link is inside an HTML comment' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      href = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/css/#{DOCS_SITE_VERIFIER_DEFAULT_THEME}-default.css"
      html = <<~HTML
        <html><head><!-- <link rel="stylesheet" href="#{href}"> --></head>
        <body><div class="main-content-wrap"><div class="paragraph"><p>hi</p></div></div></body></html>
      HTML
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        'layout: diagram_types/mindmap/index.html links no stylesheet naming theme "just-the-docs"'
      )
    end
  end

  # HIGH-1b. `data-class="main-content-wrap"` is a different attribute
  # from `class="main-content-wrap"` -- a `\b`-based regex cannot tell
  # them apart because `-` is a non-word character.
  it 'reports a page whose layout marker sits in a data-class attribute, not class' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html.sub('class="main-content-wrap"', 'data-class="main-content-wrap"')
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        'layout: diagram_types/mindmap/index.html missing layout marker "main-content-wrap"'
      )
    end
  end

  # HIGH-1c. The sole content marker, commented out, must not satisfy A3.
  it 'reports a diagram page whose only block marker is inside an HTML comment' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html_with_body('<!-- <div class="paragraph"><p>hi</p></div> -->')
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker',
        'content: _diagram_types/mindmap/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # HIGH-2a. A site-absolute ref missing the baseurl prefix must be
  # reported, even though the SAME relative path happens to exist
  # physically in `_site` (which carries no baseurl directory at all) --
  # under a real deployment at that baseurl, the un-prefixed URL 404s.
  it 'reports a stylesheet URL missing the required baseurl prefix' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html.sub(%(href="#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets), 'href="/assets')
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        'asset: /assets/css/just-the-docs-default.css (referenced by _diagram_types/mindmap/index.html) ' \
          'does not begin with baseurl "/sirena"'
      )
    end
  end

  # HIGH-2b. `/sirenax/...` is a different path than `/sirena/...` --
  # `start_with?(baseurl)` alone would strip the substring and wrongly
  # resolve it. The boundary must be segment-aware.
  it 'reports a stylesheet URL whose path merely starts with the baseurl string' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html.sub(%(href="#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets), 'href="/sirenax/assets')
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        'asset: /sirenax/assets/css/just-the-docs-default.css (referenced by _diagram_types/mindmap/index.html) ' \
          'does not begin with baseurl "/sirena"'
      )
    end
  end

  # MEDIUM-2. A query string is not part of the file path a server looks
  # up -- `?v=1` on an otherwise-valid asset URL must not turn it into a
  # false failure.
  it 'does not report a valid asset carrying a cache-busting query string as missing' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html.sub('.css">', '.css?v=1">')
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # ----------------------------------------------------------------------
  # The findings from the third Codex round, after the regex-based
  # matching from rounds 1-2 was replaced with TagTokenizer, a
  # StringScanner-based structural tag/attribute scanner (see its class
  # comment for why REXML was tried and rejected).

  # HIGH-3a. `<template>` content is real markup, but the browser never
  # renders it and nothing here clones it in -- a stylesheet link, layout
  # marker and content marker that exist only inside a <template> have not
  # actually shipped.
  it 'reports a page whose stylesheet, layout marker and content marker exist only inside a <template>' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      href = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/css/#{DOCS_SITE_VERIFIER_DEFAULT_THEME}-default.css"
      html = <<~HTML
        <html><head></head>
        <body>
          <template>
            <link rel="stylesheet" href="#{href}">
            <div class="main-content-wrap"><div class="paragraph"><p>hi</p></div></div>
          </template>
        </body></html>
      HTML
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        'layout: diagram_types/mindmap/index.html missing layout marker "main-content-wrap"',
        'layout: diagram_types/mindmap/index.html links no stylesheet naming theme "just-the-docs"',
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # HIGH-3b. Attribute parsing is grammar-based, not whitespace-shaped --
  # `src = "…"` (spaced `=`) is exactly as much a `src` attribute as
  # `src="…"`, so a missing target must still be reported.
  it 'reports a missing script asset whose src attribute has whitespace around the equals sign' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      missing = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/js/missing.js"
      html = page_html.sub('</head>', %(<script src = "#{missing}"></script></head>))
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        "asset: #{missing} (referenced by _diagram_types/mindmap/index.html) does not resolve to /assets/js/missing.js"
      )
    end
  end

  # MEDIUM-3a. `File.exist?` is true for a directory. A stylesheet href
  # that resolves to a directory sharing the asset's name is not a file a
  # server can return, so it must be reported the same as a missing one.
  it 'reports a stylesheet asset that resolves to a directory, not a file' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      FileUtils.mkdir_p(File.join(site_dir, 'assets/css/phantom.css'))
      href = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/css/phantom.css"
      html = page_html.sub('</head>', %(<link rel="stylesheet" href="#{href}"></head>))
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        "asset: #{href} (referenced by _diagram_types/mindmap/index.html) does not resolve to /assets/css/phantom.css"
      )
    end
  end

  # MEDIUM-3b. `../` in a ref can walk the resolved path outside `_site`
  # entirely, onto a real file that happens to sit next to it in `docs/`.
  # That file existing is not the asset existing.
  it 'reports a stylesheet asset whose ../ reference resolves outside _site' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      File.write(File.join(docs_dir, 'outside.css'), '/* not part of the deployed site */')
      href = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/../outside.css"
      html = page_html.sub('</head>', %(<link rel="stylesheet" href="#{href}"></head>))
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        "asset: #{href} (referenced by _diagram_types/mindmap/index.html) does not resolve to /../outside.css"
      )
    end
  end

  # BLOCKER, found by hand while re-verifying this round rather than
  # reported by Codex. `TagTokenizer#tags` must terminate on ordinary
  # HTML, which always ends in closing tags after the last opening tag.
  # The original `until @scanner.eos?` guard never became true while that
  # trailing markup stayed unconsumed once `skip_until` had nothing left
  # to match, so the verifier hung forever on every real page, not on a
  # corner case -- this pins termination with an explicit timeout so a
  # regression reads as a named failure, not a mysterious CI hang.
  it 'does not hang tokenizing a page whose only remaining markup after the last tag is closing tags' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)

      failures = Timeout.timeout(2) { verifier_for(docs_dir, site_dir).failures }
      expect(failures).to eq([])
    end
  end

  # ----------------------------------------------------------------------
  # The findings from the fourth Codex round, against the `TagTokenizer`
  # introduced to fix round 3. All three are constructed inputs Codex ran
  # against the real implementation.

  # HIGH-4a. A `<template>` nested inside another `<template>` must not let
  # the OUTER template's still-inert tail resume tokenizing as live markup.
  # `skip_uninspected_content` used to `scan_until` the FIRST `</template>`
  # unconditionally, which closes only the INNER template here -- the
  # stylesheet link, layout marker and content marker that follow it are
  # still inside the outer template and must stay inert.
  it 'reports a page whose live-looking markup sits inside a template nested in another template' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      href = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/css/#{DOCS_SITE_VERIFIER_DEFAULT_THEME}-default.css"
      html = <<~HTML
        <html><head></head>
        <body>
          <template>
            <template></template>
            <link rel="stylesheet" href="#{href}">
            <div class="main-content-wrap"><div class="paragraph"><p>hi</p></div></div>
          </template>
        </body></html>
      HTML
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        'layout: diagram_types/mindmap/index.html missing layout marker "main-content-wrap"',
        'layout: diagram_types/mindmap/index.html links no stylesheet naming theme "just-the-docs"',
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # HIGH-4b. A `<textarea>`'s content is its raw text VALUE, per the HTML5
  # spec -- markup typed there (e.g. as a code-sample placeholder) is never
  # parsed into real elements, so a stylesheet link, layout marker or
  # content marker living only inside a `<textarea>` has not actually
  # shipped, the same as script/style content.
  it 'reports a page whose live-looking markup sits only inside a textarea' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      href = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/css/#{DOCS_SITE_VERIFIER_DEFAULT_THEME}-default.css"
      html = <<~HTML
        <html><head></head>
        <body>
          <textarea>
            <link rel="stylesheet" href="#{href}">
            <div class="main-content-wrap"><div class="paragraph"><p>hi</p></div></div>
          </textarea>
        </body></html>
      HTML
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        'layout: diagram_types/mindmap/index.html missing layout marker "main-content-wrap"',
        'layout: diagram_types/mindmap/index.html links no stylesheet naming theme "just-the-docs"',
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # MEDIUM-4. The nested-directory guard added for stylesheet/script refs
  # in round 3 (`resolves_within_site_dir?`, using `.file?`) never touched
  # this SEPARATE search-index check, which still used `.exist?` --
  # `.exist?` is true for a directory, so a directory happening to sit at
  # `assets/js/search-data.json` satisfied the requirement without a real
  # search index ever being built.
  it 'reports the search index missing when a directory sits at its path instead of a file' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      search_index = File.join(site_dir, 'assets/js/search-data.json')
      FileUtils.rm(search_index)
      FileUtils.mkdir_p(search_index)

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'asset: search index "assets/js/search-data.json" missing'
      )
    end
  end

  def page_html_with_body(body_html, theme: DOCS_SITE_VERIFIER_DEFAULT_THEME, baseurl: DOCS_SITE_VERIFIER_DEFAULT_BASEURL)
    stylesheet_tag = %(<link rel="stylesheet" href="#{baseurl}/assets/css/#{theme}-default.css">)
    <<~HTML
      <html><head>#{stylesheet_tag}</head>
      <body>
        <div class="main-content-wrap">
          #{body_html}
        </div>
      </body></html>
    HTML
  end
end
