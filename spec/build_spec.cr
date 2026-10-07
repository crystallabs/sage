require "./spec_helper"

describe SSG::Builder do
  describe "classify fixture" do
    site = SSG::Builder.build(File.join(FIXTURES, "classify"), clean: true, log: IO::Memory.new)
    outdir = site.config.output_dir

    it "writes pages, resources and processed resources next to each other" do
      File.read(File.join(outdir, "blog/hello/index.html")).should contain %(<img src="./img/x.png")
      File.exists?(File.join(outdir, "blog/hello/img/x.png")).should be_true
      File.read(File.join(outdir, "blog/hello/attach/data.txt")).should eq "site=Classify page=Hello"
      File.read(File.join(outdir, "feed.xml")).should eq site.pages.size.to_s
      File.exists?(File.join(outdir, "about/photo.png")).should be_true
    end

    it "renders every format that has a matching layout" do
      xml = File.read(File.join(outdir, "blog/index.xml"))
      xml.should contain "<item><p>later</p>"
      xml.should contain "<item><p>hello"
      File.exists?(File.join(outdir, "blog/hello/index.xml")).should be_false
    end

    it "reaches formats through converters, for resources and for layouts" do
      File.read(File.join(outdir, "blog/hello/summary.txt")).should eq "Summary\n\nOf Hello.\n"
      File.read(File.join(outdir, "about/index.txt")).should eq "About\nabout\n"
      File.exists?(File.join(outdir, "blog/index.txt")).should be_false # no list.txt layout
    end

    it "imports shortcode macros everywhere, with call blocks and the page store" do
      html = File.read(File.join(outdir, "blog/sc/index.html"))
      html.should contain %(<a href="https://x.test/a">A &quot;quoted&quot; name</a>)
      html.should contain %(<a href="https://x.test/b">B</a>)
      html.should contain "<q>line one\nline two (me)</q>"
      html.should contain "hi 1"
      html.should contain "<https://x.test/a><https://x.test/b>"
    end

    it "extracts links, headings and a summary from the rendered html" do
      html = File.read(File.join(outdir, "blog/sc/index.html"))
      html.should contain %([A "quoted" name=https://x.test/a!][B=https://x.test/b!][plain=/about/])
      html.should contain %(<h1 id="first">First</h1>)
      html.should contain %(<h1 id="first-2">First</h1>)
      html.should contain "(#first=1)(#first-2=2)(#sub=2.1)(#deep=2.1.0.1)(#third=3)"
      html.should contain %(|See A "quoted" name and B and plain.|)
    end

    it "paginates html list pages" do
      File.read(File.join(outdir, "blog/index.html")).should contain "[Later][Hello]1/2 next=/blog/page/2/"
      File.read(File.join(outdir, "blog/page/2/index.html")).should contain "[Shortcodes]2/2 prev=/blog/"
      File.read(File.join(outdir, "blog/index.xml")).should contain "<item><p>later</p>" # feeds are not paginated
      File.exists?(File.join(outdir, "docs/page/2/index.html")).should be_false
    end

    it "writes pages under their parent's slug" do
      File.exists?(File.join(outdir, "renamed/child/index.html")).should be_true
      File.exists?(File.join(outdir, "sec")).should be_false
    end

    it "writes alias redirect pages" do
      File.read(File.join(outdir, "old.html")).should contain "/c/u/"
      File.exists?(File.join(outdir, "c/u/index.html")).should be_true
      File.exists?(File.join(outdir, "d/intro/index.html")).should be_true
    end

    it "highlights fenced code and leaves unknown languages plain" do
      html = File.read(File.join(outdir, "blog/sc/index.html"))
      html.should contain %(<span class="hl-)
      html.should contain %(<code class="language-nosuchlang">raw)
    end

    it "falls back to theme layouts, static files, data and macros, with the site winning" do
      File.read(File.join(outdir, "about/index.html")).should start_with "<p>About</p>" # site layout, not THEME-PAGE
      alias_html = File.read(File.join(outdir, "old-custom/index.html"))
      alias_html.should eq %(THEME-ALIAS /old-custom/ -> /c/u/ [Basic] from-theme <a href="u">t</a>)
      File.read(File.join(outdir, "css/theme.css")).should eq "theme{}"
      File.read(File.join(outdir, "css/site.css")).should contain ".nested .child" # site's site.css.scss beats theme's site.css
    end

    it "compiles scss in static directories, with private partials and theme imports" do
      css = File.read(File.join(outdir, "css/site.css"))
      css.should contain "color: #123456"   # from the site's own _vars.scss
      css.should contain ".nested .child"   # nesting compiled
      css.should contain "theme-mixin: yes" # imported from the theme's static dir
      File.exists?(File.join(outdir, "css/_vars.scss")).should be_false
      File.exists?(File.join(outdir, "css/_theme_mixins.scss")).should be_false
      File.exists?(File.join(outdir, "css/site.css.scss")).should be_false
      File.read(File.join(outdir, "css/theme.css")).should eq "theme{}"
    end

    it "restricts a page to the formats named in outputs, and to none for an empty list" do
      File.exists?(File.join(outdir, "d/intro/index.html")).should be_true
      File.exists?(File.join(outdir, "d/intro/index.txt")).should be_false       # outputs: [html]
      File.exists?(File.join(outdir, "renamed/silent")).should be_false          # outputs: []
      File.read(File.join(outdir, "renamed/index.html")).should contain "Silent" # still listed
      File.exists?(File.join(outdir, "tags/index.xml")).should be_false          # cascaded onto itself
      File.exists?(File.join(outdir, "tags/a/index.xml")).should be_false        # and onto the term pages
      File.exists?(File.join(outdir, "tags/a/index.html")).should be_true
    end

    it "does not write drafts" do
      File.exists?(File.join(outdir, "blog/hidden/index.html")).should be_false
    end
  end

  describe "rebuilds" do
    root = File.join(FIXTURES, "classify")
    it "leaves unchanged files alone unless asked to touch them" do
      site = SSG::Builder.build(root, clean: true, log: IO::Memory.new)
      path = File.join(site.config.output_dir, "about/index.html")
      before = File.info(path).modification_time
      sleep 20.milliseconds
      log = IO::Memory.new
      SSG::Builder.build(root, log: log)
      log.to_s.should match(/: 0 written, \d+ unchanged/)
      File.info(path).modification_time.should eq before
      SSG::Builder.build(root, touch: true, log: IO::Memory.new)
      File.info(path).modification_time.should be > before
    end

    it "lists orphaned output files without building" do
      site = SSG::Builder.build(root, clean: true, log: IO::Memory.new)
      outdir = site.config.output_dir
      SSG::Builder.orphans(root).should eq [] of String

      stray = File.join(outdir, "old/leftover.html")
      hidden = File.join(outdir, ".stale")
      Dir.mkdir_p(File.dirname(stray))
      File.write(stray, "x")
      File.write(hidden, "x")
      removed = File.join(outdir, "about/index.html")
      File.delete(removed)

      list = SSG::Builder.orphans(root)
      list.should eq [hidden, stray]
      File.exists?(removed).should be_false # nothing was built

      d = SSG::Builder.diff(root)
      d.dir.should eq outdir
      io = IO::Memory.new
      SSG::Builder.print_diff(d, io, :extra, true, base: outdir).should be_true
      io.to_s.should eq ".stale\nold/leftover.html\n"
      io = IO::Memory.new
      SSG::Builder.print_diff(d, io, :extra, true, nul: true, base: outdir)
      io.to_s.should eq ".stale\0old/leftover.html\0"
    end

    it "compares the plan with another directory without building" do
      SSG::Builder.build(root, clean: true, log: IO::Memory.new)
      other = File.join(FIXTURES, "..", "out", "diff[*]") # no glob may choke on the name
      FileUtils.rm_rf(other)
      FileUtils.cp_r(SSG::Config.load(root).output_dir, other)
      File.rename(File.join(other, "about/index.html"), File.join(other, "About.html"))
      File.delete(File.join(other, "docs/index.html"))
      File.write(File.join(other, "stray.html"), "x")
      Dir.mkdir_p(File.join(other, "gen"))
      File.write(File.join(other, "gen/x.bak"), "x")

      SSG::Builder.diff(root).empty?.should be_true # the output directory itself

      d = SSG::Builder.diff(root, other)
      d.dir.should eq other
      d.extra.should eq ["About.html", "gen/x.bak", "stray.html"]
      d.missing.map(&.rel).should eq ["about/index.html", "docs/index.html"]
      d.renamed.map { |r, j| {r, j.rel} }.should eq [{"About.html", "about/index.html"}]
      File.exists?(File.join(other, "docs/index.html")).should be_false # nothing was built

      SSG::Builder.diff(root, other, strict: true).renamed.should be_empty
      SSG::Builder.diff(root, other, ["*.bak"]).extra.should eq ["About.html", "stray.html"]
      SSG::Builder.diff(root, other, ["gen"]).extra.should eq ["About.html", "stray.html"]
      SSG::Builder.diff(root, other, ["gen/"]).extra.should eq ["About.html", "stray.html"]
      SSG::Builder.diff(root, other, ["gen/*.bak", "docs/index.html"]).missing.map(&.rel).should eq ["about/index.html"]

      io = IO::Memory.new
      SSG::Builder.print_diff(d, io, base: root).should be_true
      io.to_s.should eq "~ About.html\tabout/index.html\n+ docs/index.html\tlist /docs/\n- gen/x.bak\n- stray.html\n"
      io = IO::Memory.new
      SSG::Builder.print_diff(d, io, :missing, base: File.dirname(other))
      io.to_s.should eq "diff[*]/about/index.html\t../fixtures/classify/content/about.md\ndiff[*]/docs/index.html\tlist /docs/\n"
      io = IO::Memory.new
      SSG::Builder.print_diff(d, io, :missing, true, base: other)
      io.to_s.should eq "about/index.html\ndocs/index.html\n"
    end

    it "overrides the base url" do
      site = SSG::Builder.build(root, base_url: "https://preview.test", log: IO::Memory.new)
      site.config.base_url.should eq "https://preview.test/"
      site.absolute_url("/x/").should eq "https://preview.test/x/"
    end
  end

  describe "example site" do
    site = SSG::Builder.build(EXAMPLE, clean: true, log: IO::Memory.new)
    outdir = site.config.output_dir

    it "produces the expected files" do
      %w[
        index.html index.xml about/index.html blog/index.html blog/index.xml
        2026/09/hello-world/index.html 2026/09/hello-world/index.xml 2026/09/hello-world/img/diagram.svg
        2026/09/hello-world/notes.txt 2026/09/second-post/index.html docs/index.html docs/guide/index.html
        tags/index.html tags/crystal/index.html tags/intro/index.html categories/news/index.html
        sitemap.xml css/style.css blog/page/2/index.html 2023/07/unix-history/index.html unix-history/index.html css/highlight.css
      ].each { |f| File.exists?(File.join(outdir, f)).should be_true }
      File.exists?(File.join(outdir, "blog/draft/index.html")).should be_false
    end

    it "emits the dark highlighting theme under prefers-color-scheme" do
      css = File.read(File.join(outdir, "css/highlight.css"))
      css.should contain "@media (prefers-color-scheme: dark) {"
      css.should contain SSG::Processors::Markdown.css("github-dark")
    end

    it "uses section layouts and processes .md.j2 before markdown" do
      File.read(File.join(outdir, "2026/09/hello-world/index.html")).should contain "<title>Blog: Hello, World</title>"
      File.read(File.join(outdir, "2026/09/second-post/index.html")).should contain "<strong>Example Site</strong>"
    end

    it "renders the converted Hugo article with its automatic links, toc and series box" do
      html = File.read(File.join(outdir, "2023/07/unix-history/index.html"))
      html.should_not contain "{{"
      html.scan(/<h[2-6] id=/).size.should eq 37
      html.should contain "<h2>Automatic Links</h2>"
      html.should contain %(<a href="/2023/08/unix-philosophy/">Unix philosophy</a>)
      html.should contain "(this article)"
      html.should contain %(<a href="#introduction">Introduction</a>)
      File.read(File.join(outdir, "2023/08/unix-philosophy/index.html")).should contain "understand Unix<br>are condemned"
    end

    it "gives feeds the html content of child pages" do
      File.read(File.join(outdir, "blog/index.xml")).should contain "&lt;p&gt;"
      File.read(File.join(outdir, "sitemap.xml")).should contain "https://example.com/2026/09/hello-world/"
    end
  end
  describe "minima theme example site" do
    site = SSG::Builder.build(MINIMA, clean: true, log: IO::Memory.new)
    outdir = site.config.output_dir

    it "produces the expected files" do
      %w[index.html index.xml index.json 404.html about/index.html search/index.html
        posts/index.html posts/unix-history/index.html posts/unix-philosophy/index.html unix-history/index.html
        tags/index.html tags/unix/index.html series/index.html series/unix/index.html
        css/minima.css js/minima.js js/search.js js/fuse.basic.min.js img/link-external.svg
      ].each { |f| File.exists?(File.join(outdir, f)).should be_true }
      File.exists?(File.join(outdir, "404/index.html")).should be_false
    end

    it "renders the home page with posts grouped by series" do
      html = File.read(File.join(outdir, "index.html"))
      html.should contain "<h3 class=\"mt-6 mb-0 text-2xl font-semibold\">Unix</h3>"
      html.should contain "<p>Unix history and philosophy</p>"
      html.should contain %(<a class="text-lg font-bold" href="/posts/unix-history/">)
      html.should contain %(window.minima = {)
      html.should contain %("theme":"light")
    end

    it "renders an article with toc, series box, links box and highlighted code" do
      html = File.read(File.join(outdir, "posts/unix-history/index.html"))
      html.should contain "<h2>Table of Contents</h2>"
      html.should contain "Article Collection"
      html.should contain "(this article)"
      html.should contain "<h2>Links</h2>"
      html.should contain %(href="/tags/unix/">#unix</a>)
      File.read(File.join(outdir, "posts/unix-philosophy/index.html")).should contain %(<span class="hl-)
    end

    it "numbers citations in order of first use and lists only the cited sources" do
      html = File.read(File.join(outdir, "citations/index.html"))
      html.should contain %(first use <a href="#ref-1">[1]</a>, not the order of the list <a href="#ref-2">[2]</a>.)
      html.should contain %(keeps its number <a href="#ref-1">[1]</a>.)
      html.should contain %(<div id="ref-1"><p>[1] A. Author.)
      html.should contain %(<div id="ref-2"><p>[2] B. Author, <em>Second Source</em>.)
      html.should_not contain "Never Cited"
    end

    it "fails the build on error(), which cite() uses for an unknown key" do
      env = SSG::TemplateEnv.build(site)
      expect_raises(Crinja::RuntimeError, "boom") { env.from_string(%({{ error("boom") }})).render }
      env.from_string(%(ok{{ error("") }})).render.should eq "ok"
    end

    it "writes a valid search index and feeds" do
      docs = JSON.parse(File.read(File.join(outdir, "index.json"))).as_a
      docs.map(&.["title"].as_s).sort!.should eq ["About", "Citations", "History of Unix, BSD, GNU, and Linux", "The Unix Philosophy"]
      docs.find! { |d| d["title"] == "The Unix Philosophy" }["content"].as_s.should contain "Henry Spencer"
      xml = File.read(File.join(outdir, "index.xml"))
      xml.should contain "<title>Minima Example</title>"
      xml.should contain "<pubDate>Tue, 01 Aug 2023"
      File.read(File.join(outdir, "series/unix/index.xml")).should contain "on Minima Example</title>"
    end

    it "uses file-style urls and search options" do
      File.read(File.join(outdir, "404.html")).should contain "404 Not Found"
      File.read(File.join(outdir, "search/index.html")).should contain "data-options="
    end
  end
end
