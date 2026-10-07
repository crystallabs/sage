require "./spec_helper"

describe SSG::Config do
  it "passes markdown options through" do
    data = SSG::FrontMatter::Data.new
    data["markdown"] = YAML.parse("smart: true\nsafe: true")
    config = SSG::Config.new("/x", data)
    config.markdown.smart?.should be_true
    config.markdown.safe?.should be_true
    config.markdown.gfm?.should be_false
    md = SSG::Processors::Markdown.new(config.markdown)
    site = load_fixture("classify")
    ctx = SSG::Chain::Context.new(site, SSG::TemplateEnv.build(site))
    String.new(md.call(%(say "hi" <b>x</b>).to_slice, ctx)).should contain "&quot;hi&quot;".sub("&quot;hi&quot;", "“hi”")
    String.new(md.call(%(<b>x</b>).to_slice, ctx)).should contain "<!-- raw HTML omitted -->"
  end

  it "takes a heading's id from a trailing {#id}, else from its text" do
    md = SSG::Processors::Markdown.new
    site = load_fixture("classify")
    ctx = SSG::Chain::Context.new(site, SSG::TemplateEnv.build(site))
    html = String.new(md.call("## The *Intro* {#intro}\n\n## Plain one\n\n### Again {#intro}\n".to_slice, ctx))
    html.should contain %(<h2 id="intro">The <em>Intro</em></h2>)
    html.should contain %(<h2 id="plain-one">Plain one</h2>)
    html.should contain %(<h3 id="intro-2">Again</h3>)
  end

  it "keeps inline markup between an ampersand and a later semicolon" do
    md = SSG::Processors::Markdown.new
    site = load_fixture("classify")
    ctx = SSG::Chain::Context.new(site, SSG::TemplateEnv.build(site))
    html = String.new(md.call("AT&T and [a link](/x) and `code`; then &mdash; &#65; &amp; &nosuch; R&D\n".to_slice, ctx))
    html.should contain %(AT&amp;T and <a href="/x">a link</a> and <code>code</code>; then — A &amp; &amp;nosuch; R&amp;D)
  end

  it "does not autolink a url that is already the text of an html link" do
    data = SSG::FrontMatter::Data.new
    data["markdown"] = YAML.parse("gfm: true\nautolink: true")
    md = SSG::Processors::Markdown.new(SSG::Config.new("/x", data).markdown)
    site = load_fixture("classify")
    ctx = SSG::Chain::Context.new(site, SSG::TemplateEnv.build(site))
    html = String.new(md.call(%(At <a href="https://e.org/">https://e.org/</a>. Also https://f.org/x and [https://g.org/](/g).\n).to_slice, ctx))
    html.should contain %(At <a href="https://e.org/">https://e.org/</a>. Also <a href="https://f.org/x">https://f.org/x</a> and <a href="/g">https://g.org/</a>.)
  end

  it "turns highlighting off or picks a theme" do
    data = SSG::FrontMatter::Data.new
    data["markdown"] = YAML.parse("highlight: false")
    SSG::Config.new("/x", data).highlight_theme.should be_nil
    data["markdown"] = YAML.parse("highlight: monokai\nline_numbers: true")
    c = SSG::Config.new("/x", data)
    c.highlight_theme.should eq "monokai"
    c.line_numbers?.should be_true
    SSG::Config.new("/x", SSG::FrontMatter::Data.new).highlight_theme.should eq "default-dark"
    expect_raises(SSG::Error, /unknown highlight theme/) { SSG::Processors::Markdown.formatter("no-such-theme", false) }
  end

  it "accepts one theme or a list and rejects missing ones" do
    root = File.join(FIXTURES, "classify")
    data = SSG::FrontMatter::Data.new
    data["theme"] = YAML.parse("basic")
    c = SSG::Config.new(root, data)
    c.themes.should eq ["basic"]
    c.layout_dirs.should eq [File.join(root, "layouts"), File.join(root, "themes/basic/layouts")]
    data["theme"] = YAML.parse("[basic, basic]")
    SSG::Config.new(root, data).themes.should eq ["basic", "basic"]
    data["theme"] = YAML.parse("nope")
    expect_raises(SSG::Error, /theme not found/) { SSG::Config.new(root, data) }
  end

  it "reads the sass output style" do
    data = SSG::FrontMatter::Data.new
    data["sass"] = YAML.parse("style: compressed")
    SSG::Config.new("/x", data).sass_style.should eq "compressed"
    SSG::Processors::Sass.style("compressed").should eq Sass::OutputStyle::COMPRESSED
    expect_raises(SSG::Error, /unknown sass style/) { SSG::Processors::Sass.style("tiny") }
  end

  it "rejects unknown markdown options" do
    data = SSG::FrontMatter::Data.new
    data["markdown"] = YAML.parse("bogus: true")
    expect_raises(SSG::Error, /unknown markdown option bogus/) { SSG::Config.new("/x", data) }
  end
end
