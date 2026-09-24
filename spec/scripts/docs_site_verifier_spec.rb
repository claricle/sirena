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

# -- fixture builders -------------------------------------------------
# `def`s, not `let`s: every one takes arguments (rspec.rubystyle.guide has
# no rule against this; `let` has no arity, see dev.md's RSpec `let` note).
module DocsSiteVerifierSpecHelpers
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

RSpec.describe Sirena::DocsSiteVerifier do
  include DocsSiteVerifierSpecHelpers

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

  # `Pathname#exist?` is true for a DIRECTORY too, so a directory named
  # `index.html` satisfied the manifest check while no HTML file was there.
  # The file already uses `.file?` where it matters (the search index, and
  # the asset resolver, which carries a comment saying exactly this) -- these
  # two sites were the ones that missed it. Manifest completeness has TWO
  # such guards -- collection path and include path -- and they need their
  # own example each: a spec built against one cannot exercise the other,
  # since `include_path_for('mindmap')` and the collection path are
  # different strings.
  it 'does not accept a directory standing in for the collection-path page' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      FileUtils.rm_f(File.join(site_dir, 'diagram_types/mindmap/index.html'))
      FileUtils.mkdir_p(File.join(site_dir, 'diagram_types/mindmap/index.html'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'manifest: _diagram_types/mindmap.adoc missing at diagram_types/mindmap/index.html'
      )
    end
  end

  it 'does not accept a directory standing in for the include-path page' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      FileUtils.rm_f(File.join(site_dir, '_diagram_types/mindmap/index.html'))
      FileUtils.mkdir_p(File.join(site_dir, '_diagram_types/mindmap/index.html'))

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'manifest: _diagram_types/mindmap.adoc missing at _diagram_types/mindmap/index.html'
      )
    end
  end

  # An EMPTY attribute value is present-but-broken, not absent. Mapping it to
  # `true` dropped it from every downstream check that greps for Strings, so a
  # `<script src="">` — a script tag that loads nothing — was invisible.
  #
  # **This corrects the data model; it does not change a verdict today.** The
  # asset check filters a non-site-absolute ref before resolving it, so an
  # empty ref is collected and then skipped either way. Said plainly rather
  # than claimed as a closed false negative, because the honest claim is the
  # narrower one.
  #
  # Two earlier versions of this spec were vacuous and the mutation caught
  # both: one asserted the theme-stylesheet failure, which fires with or
  # without the sentinel, and one asserted an asset failure that never fires.
  # This asserts the thing that actually differs.
  #
  # Nokogiri cannot tell `<script src>` from `<script src="">` — both give ""
  # — and nothing tested an attribute for `true`, so the sentinel was dead
  # weight as well as harmful.
  it 'keeps an empty attribute value instead of turning it into true' do
    Dir.mktmpdir do |tmp|
      _docs_dir, site_dir = build_valid_site(tmp)
      html = page_html.sub('</head>', '<script src=""></script></head>')
      path = File.join(site_dir, 'pages/comparison/index.html')
      write_page(site_dir, 'pages/comparison/index.html', html)

      page = Sirena::DocsSiteVerifier::Page.new(path, site_dir)

      expect(page.script_srcs).to eq([''])
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

      # MEDIUM-10, found by Codex. The image-page body used to be
      # `<div class="imageblock">x</div>` -- artificial text that masked
      # the real shape entirely. A real Asciidoctor `imageblock` (see
      # https://docs.asciidoctor.org html5 converter output) is
      # `<div class="imageblock"><div class="content"><img ...></div></div>`
      # -- `alt` is an attribute, not a text node, so a genuine image-only
      # page has NO text at all. Confirmed directly:
      # `Nokogiri::HTML5.parse(real_imageblock_html).text == ""`.
      bodies = {
        'table-page' => '<table class="tableblock"><tr><td>x</td></tr></table>',
        'list-page' => '<ul class="ulist"><li>x</li></ul>',
        'listing-page' => '<div class="listingblock">x</div>',
        'image-page' => '<div class="imageblock"><div class="content">' \
                         '<img src="diagram.png" alt="Example"></div></div>',
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

  # Example 12d — MEDIUM found by Codex round 6. `renders_content?` counted
  # `<img>` as visible content but nothing else non-text, and `rendered_text`
  # stripped `<textarea>` alongside script/style/template as if its content
  # were equally invisible. Both are real Asciidoctor 2.0.26 converter
  # outputs, not hypothetical shapes:
  # `Asciidoctor.convert('video::dQw4w9WgXcQ[youtube]')` ->
  # `<div class="videoblock"><div class="content"><iframe src="..."
  # ...></iframe></div></div>` (no text, no img);
  # `Asciidoctor.convert('pass:[<textarea>Visible</textarea>]')` ->
  # `<div class="paragraph"><p><textarea>Visible</textarea></p></div>` (a
  # browser renders "Visible" inside the widget, unlike script/style/template
  # content, which never reaches the page). Confirmed directly against the
  # installed gem before this fix: both bodies made `renders_content?`
  # return `false`.
  it 'passes a video-only page and a textarea-content page' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      %w[video-page textarea-page].each { |name| write_source(docs_dir, name) }

      bodies = {
        'video-page' => '<div class="videoblock"><div class="content">' \
                         '<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ" ' \
                         'frameborder="0" allowfullscreen></iframe></div></div>',
        'textarea-page' => '<div class="paragraph"><p><textarea>Visible</textarea></p></div>',
      }
      bodies.each do |name, body|
        write_page(site_dir, "diagram_types/#{name}/index.html", page_html_with_body(body))
        write_page(site_dir, "_diagram_types/#{name}/index.html", page_html_with_body(body))
      end

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # Example 12e — MEDIUM found by Codex round 7, both directions of the same
  # boundary Example 12d fixed for `img`/`iframe`/`textarea`.
  #
  # Direction 1 (false negative): Asciidoctor's own image converter supports
  # `opts=inline,format=svg`, which embeds the raw `<svg>` markup directly
  # instead of wrapping it in an `<img>`. Confirmed against the installed
  # gem: `Asciidoctor.convert('image::path[opts=inline,format=svg]')` ->
  # `<div class="imageblock"><div class="content"><svg ...>...</svg>
  # </div></div>` -- no text node, no `<img>`, no `<iframe>`, yet a browser
  # shows the shape. `renders_content?` must count `<svg>` the same way it
  # already counts `<img>`/`<iframe>`.
  #
  # Direction 2 (false positive, the opposite mistake): the HTML5 boolean
  # `hidden` attribute makes a browser render an element `display: none`
  # regardless of its text content. Confirmed against the installed gem:
  # `Asciidoctor.convert('pass:[<span hidden>Invisible</span>]')` ->
  # `<div class="paragraph"><p><span hidden>Invisible</span></p></div>` --
  # a real, valid block marker, whose only text is a string a browser never
  # shows. `rendered_text` must exclude `[hidden]` elements, not just the
  # element-NAME-based SKIPPED/INVISIBLE_CONTENT_ELEMENTS lists, or a page
  # with nothing but hidden text reads as "renders content" when it renders
  # none.
  #
  # Direction 2b (spec-auditor gap, round 8): the two shapes above both put
  # the discriminating content as a CHILD of the `[hidden]` element, so
  # neither can tell "unlink the whole `[hidden]` element" apart from
  # "unlink only its children" -- a strictly weaker fix that would still
  # pass both. `hidden-svg-page` puts `hidden` directly ON the
  # content-bearing tag (`<svg hidden>`, not a wrapper around it): a
  # children-only unlink would leave the now-childless `<svg>` tag in the
  # DOM, where `renders_content?`'s `'img, iframe, svg'` selector would
  # still find it and wrongly report the page as showing content, even
  # though a browser never renders a `hidden` element at all. Confirmed
  # directly: reverting `rendered_text`'s `[hidden]` unlink to
  # `.each { |el| el.children.unlink }` leaves this page's `failures`
  # empty; the real code (unlinking the element itself) correctly reports it.
  it 'rejects a hidden-text-only page and accepts an inline-SVG-only page' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      %w[hidden-text-page inline-svg-page hidden-svg-page].each { |name| write_source(docs_dir, name) }

      bodies = {
        'hidden-text-page' => '<div class="paragraph"><p><span hidden>Invisible</span></p></div>',
        'inline-svg-page' => '<div class="imageblock"><div class="content">' \
                              '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">' \
                              '<rect width="10" height="10" fill="red"/></svg></div></div>',
        'hidden-svg-page' => '<div class="imageblock"><div class="content">' \
                              '<svg hidden xmlns="http://www.w3.org/2000/svg" width="10" height="10">' \
                              '<rect width="10" height="10" fill="red"/></svg></div></div>',
      }
      bodies.each do |name, body|
        write_page(site_dir, "diagram_types/#{name}/index.html", page_html_with_body(body))
        write_page(site_dir, "_diagram_types/#{name}/index.html", page_html_with_body(body))
      end

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/hidden-text-page/index.html renders no text in main-content-wrap',
        'content: _diagram_types/hidden-text-page/index.html renders no text in main-content-wrap',
        'content: diagram_types/hidden-svg-page/index.html renders no text in main-content-wrap',
        'content: _diagram_types/hidden-svg-page/index.html renders no text in main-content-wrap'
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
  # asset; it must be reported exactly once, attributed to the FIRST
  # page collected (`refs[ref] ||= page.rel_path`), not whichever page
  # happens to be walked last. A mutant that flips `||=` to `=` reports
  # the same count with the same asset name and stayed green here until
  # the referencing page itself was pinned.
  it 'reports one missing asset referenced by three pages exactly once, attributed to the first' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      missing_script = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/js/shared-missing.js"
      write_page(site_dir, 'diagram_types/mindmap/index.html', page_html(extra: { script: missing_script }))
      write_page(site_dir, '_diagram_types/mindmap/index.html', page_html(extra: { script: missing_script }))
      write_page(site_dir, 'pages/other/index.html', page_html(extra: { script: missing_script }))

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures.length).to eq(1)
      # '_diagram_types/...' sorts before 'diagram_types/...' and
      # 'pages/...' under Dir.glob's default sorted order.
      expect(failures.first).to eq(
        "asset: #{missing_script} (referenced by _diagram_types/mindmap/index.html) " \
          'does not resolve to /assets/js/shared-missing.js'
      )
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

      # FOUR failures, not two. A marker commented out of the page renders
      # nothing, so the page fails on both halves -- missing marker AND no
      # rendered text. The second half is what catches a page that KEEPS its
      # marker and still shows nothing, which the marker check alone passed.
      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker',
        'content: _diagram_types/mindmap/index.html has no recognized Asciidoctor block marker',
        'content: diagram_types/mindmap/index.html renders no text in main-content-wrap',
        'content: _diagram_types/mindmap/index.html renders no text in main-content-wrap'
      )
    end
  end

  # HIGH-1d. Marker presence is a PROXY for "this page has content".
  # A page can carry the marker and render nothing at all, which is what
  # the marker check alone passed for the whole life of this verifier.
  it 'reports a diagram page carrying a block marker that renders no text' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html_with_body('<div class="paragraph"></div>')
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/mindmap/index.html renders no text in main-content-wrap',
        'content: _diagram_types/mindmap/index.html renders no text in main-content-wrap'
      )
    end
  end

  # HIGH-2/3, and the shape matters. The old scanner counted `</template>`
  # occurrences, so the same characters inside an attribute value or a
  # `<script>` string CLOSED a skip that was still open -- and everything
  # after it, still inside the template and therefore inert, was read as
  # live markup. So the discriminating input is a trap INSIDE a template
  # followed by content that must stay inert.
  #
  # A trap followed by genuinely live content proves nothing: both the old
  # scanner and a real parser pass it. That version of this spec stayed
  # green against the reverted file, which is how it was caught.
  {
    'an attribute value' => '<div data-x="</template>"></div>',
    'a script string' => '<script>var s = "</template>";</script>'
  }.each do |placement, trap|
    it "does not read template content as live when #{placement} holds a closing tag" do
      Dir.mktmpdir do |tmp|
        docs_dir, site_dir = build_valid_site(tmp)
        html = page_html_with_body(
          %(<template>#{trap}<div class="paragraph">Inert</div></template>),
        )
        write_page(site_dir, 'diagram_types/mindmap/index.html', html)
        write_page(site_dir, '_diagram_types/mindmap/index.html', html)

        expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
          'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker',
          'content: _diagram_types/mindmap/index.html has no recognized Asciidoctor block marker',
          'content: diagram_types/mindmap/index.html renders no text in main-content-wrap',
          'content: _diagram_types/mindmap/index.html renders no text in main-content-wrap'
        )
      end
    end
  end

  # The other direction, and it is the one a scanner got wrong: an UNCLOSED
  # `<template>` swallows everything after it, exactly as a browser does, so
  # that content is genuinely inert and the page really does render nothing.
  # The old scanner's `scan_until` found no closing tag, left the position
  # unmoved, and carried on reading the swallowed markup as live.
  it 'treats markup after an unclosed template as inert, not live' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html_with_body('<template><div class="paragraph">Swallowed</div>')
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker',
        'content: _diagram_types/mindmap/index.html has no recognized Asciidoctor block marker',
        'content: diagram_types/mindmap/index.html renders no text in main-content-wrap',
        'content: _diagram_types/mindmap/index.html renders no text in main-content-wrap'
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

  # MEDIUM-2, the other half. The same comment (scripts/verify_docs_site.rb)
  # names a fragment alongside a query string; only the query string had a
  # spec until this one.
  it 'does not report a valid asset carrying a URL fragment as missing' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html.sub('.css">', '.css#section">')
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # ----------------------------------------------------------------------
  # The findings from the third Codex round, after the regex-based
  # matching from rounds 1-2 was replaced with TagTokenizer -- originally a
  # StringScanner-based structural tag/attribute scanner, later rewritten
  # onto Nokogiri::HTML5 (see its class comment for both changes and why
  # REXML was tried and rejected in between).

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
  #
  # DIAGNOSTIC, not a live risk today: `TagTokenizer` is now a thin
  # `Nokogiri::HTML5` wrapper (see its class comment), which does not hang
  # on ordinary valid HTML regardless of anything in this file. Keep this
  # spec; it becomes the only check that catches a regression back to a
  # hand-rolled/backtracking tokenizer.
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

  # ----------------------------------------------------------------------
  # The findings from the fifth Codex round, run against the real
  # just-the-docs theme via a live Jekyll build. Each is reproduced here as
  # a constructed input against the implementation directly.

  # HIGH-5. just-the-docs' own `_layouts/default.html` nests BOTH the real
  # content region (`<main>`) and the theme footer (`<footer>`, sibling of
  # `<main>`) inside `.main-content-wrap`:
  #   <div class="main-content-wrap">
  #     <div id="main-content" class="main-content">
  #       <main>...page content...</main>
  #       <footer>...back-to-top / "This site uses Just the Docs" text...</footer>
  #     </div>
  #   </div>
  # The footer ALWAYS renders visible text, so scoping `rendered_text` to
  # `.main-content-wrap` can never see an empty page -- confirmed against a
  # real Jekyll build (theme just-the-docs, back_to_top enabled, an
  # otherwise-empty page): rendered `<main>` text was "", but the verifier's
  # `.main-content-wrap`-scoped text was "Back to top This site uses Just
  # the Docs, a documentation theme for Jekyll."
  it 'reports empty content even when the theme footer pads .main-content-wrap with visible text' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      href = "#{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}/assets/css/#{DOCS_SITE_VERIFIER_DEFAULT_THEME}-default.css"
      html = <<~HTML
        <html><head><link rel="stylesheet" href="#{href}"></head>
        <body>
          <div class="main-content-wrap">
            <div id="main-content" class="main-content">
              <main><div class="paragraph"></div></main>
              <footer>
                <p><a href="#top">Back to top</a></p>
                <div>This site uses <a href="https://github.com/just-the-docs/just-the-docs">Just the Docs</a>, a documentation theme for Jekyll.</div>
              </footer>
            </div>
          </div>
        </body></html>
      HTML
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      # MEDIUM-9, found by Codex. The old message always named
      # `LAYOUT_BODY_MARKER`, which was false here: `rendered_text` reads
      # `<main>` when it exists (per the HIGH-5 fix above), so THIS page's
      # empty-content failure is about `<main>`, not `.main-content-wrap`
      # -- the wrapper genuinely renders text (the footer) and saying so
      # would contradict the fix this spec exists to pin.
      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/mindmap/index.html renders no text in main',
        'content: _diagram_types/mindmap/index.html renders no text in main'
      )
    end
  end

  # MEDIUM-5. Jekyll's documented array shorthand for `collections:`
  # (`collections: [diagram_types]`, normalized by Jekyll itself into a
  # Hash with default options) is a plain Array once this script parses
  # `_config.yml` with `YAML.safe_load_file` -- Jekyll's own normalization
  # never runs here. `Hash#dig('collections', 'diagram_types', 'permalink')`
  # then calls `Array#dig('diagram_types', 'permalink')`, and Array#dig
  # requires an Integer index, so a String key raises TypeError. Verified
  # directly: `{"collections" => ["diagram_types"]}.dig("collections",
  # "diagram_types", "permalink")` raises
  # "TypeError: no implicit conversion of String into Integer". The
  # contract of `failures` is an array of strings, never a raised error.
  it 'reports a config failure instead of raising when collections uses the array shorthand' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      write_config(docs_dir, 'collections' => ['diagram_types'])

      expect { verifier_for(docs_dir, site_dir).failures }.not_to raise_error

      failures = verifier_for(docs_dir, site_dir).failures
      expect(failures).to include(
        'config: collections.diagram_types.permalink is nil, expected "/:collection/:path/"'
      )
    end
  end

  # MEDIUM-6. `Page#markup` used to strip comments with
  # `content.gsub(/<!--.*?-->/m, '')` BEFORE handing markup to Nokogiri.
  # That regex looks for the first `<!--` and the first `-->` after it --
  # so a `<!--`-shaped STRING inside a `<script>`, followed later by a
  # real `<!-- comment -->`, made the lazy match span from the fake open to
  # the real close, deleting every real element in between. Verified
  # directly: `%(<script>const marker = "<!--";</script><div
  # class="paragraph">Visible</div><!-- comment -->).gsub(/<!--.*?-->/m,
  # '')` leaves `<script>const marker = "` with everything after it gone,
  # including the live `<div>`. A real HTML5 parser needs no such
  # preprocessing -- Nokogiri already excludes comment nodes structurally
  # (verified: a `<!-- comment -->` sibling of a live `<div>` never
  # contributes to `.text`, and never shows up as a `document.css` match),
  # so the pre-strip only ever subtracts content it did not need to.
  it 'does not delete real content between a false comment-open in a script and a later real comment' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html_with_body(
        %(<script>const marker = "<!--";</script><div class="paragraph"><p>hi</p></div><!-- trailing comment -->)
      )
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end

  # MEDIUM-7. `class_tokens` read from `tags`, which (deliberately, per the
  # `TagTokenizer` class comment) still reports a skipped element ITSELF --
  # only its children are dropped. That means the skipped element's OWN
  # `class` attribute leaked into `class_tokens` too, so
  # `<template class="paragraph">` alone satisfied the content-marker
  # check even though a `<template>`'s content never ships. The visible
  # fallback text elsewhere on the page carries no marker at all, so the
  # only Asciidoctor marker on the page is the inert one.
  it 'reports no recognized marker when the only marker class sits on a skipped element itself' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      html = page_html_with_body(%(<template class="paragraph"></template><p>Visible fallback text</p>))
      write_page(site_dir, 'diagram_types/mindmap/index.html', html)
      write_page(site_dir, '_diagram_types/mindmap/index.html', html)

      expect(verifier_for(docs_dir, site_dir).failures).to contain_exactly(
        'content: diagram_types/mindmap/index.html has no recognized Asciidoctor block marker',
        'content: _diagram_types/mindmap/index.html has no recognized Asciidoctor block marker'
      )
    end
  end

  # MEDIUM-8, found by Codex against a real Jekyll config load. Jekyll's own
  # config loader (`Jekyll::Configuration#safe_load_file`, backed by the
  # `safe_yaml` gem) accepts YAML anchors/aliases -- a documented, ordinary
  # way to avoid repeating `permalink:` across every collection -- and
  # resolves them correctly. Plain `YAML.safe_load_file` (what this script
  # uses) does NOT allow aliases unless told to, and raises instead of
  # returning a Hash. Verified directly: the same `_config.yml` shape
  # (`collections: {diagram_types: {<<: *defaults}}`) that
  # `Jekyll::Configuration.new.safe_load_file` resolves to
  # `{"permalink"=>"/:collection/:path/"}` makes plain
  # `YAML.safe_load_file` raise `Psych::AliasesNotEnabled`. A config Jekyll
  # itself builds successfully must not crash this verifier.
  it 'reads a real _config.yml that uses a YAML anchor/alias for collection options' do
    Dir.mktmpdir do |tmp|
      docs_dir, site_dir = build_valid_site(tmp)
      config_yaml = <<~YAML
        defaults: &defaults
          permalink: "/:collection/:path/"
        theme: #{DOCS_SITE_VERIFIER_DEFAULT_THEME}
        baseurl: #{DOCS_SITE_VERIFIER_DEFAULT_BASEURL}
        search_enabled: true
        include:
          - _diagram_types
        collections:
          diagram_types:
            <<: *defaults
      YAML
      File.write(File.join(docs_dir, '_config.yml'), config_yaml)

      expect { verifier_for(docs_dir, site_dir).failures }.not_to raise_error
      expect(verifier_for(docs_dir, site_dir).failures).to eq([])
    end
  end
end
