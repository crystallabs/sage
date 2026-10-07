require "./spec_helper"

private ROOT = File.join(FIXTURES, "classify")

private def titles(*filters : String) : Array(String)
  Sage::Listing.pages(ROOT, filters.to_a).map(&.title)
end

private def printed(pages, **opts) : String
  String.build { |io| Sage::Listing.print(pages, io, **opts, base: ROOT) }
end

describe Sage::Listing do
  it "lists every page that has a source file, drafts included, by source path" do
    Sage::Listing.pages(ROOT).map(&.title).should eq ["About", "Hello", "Hidden", "Later", "Shortcodes", "Custom", "Intro", "Home",
                                                      "Child", "Section", "Silent", "All tags"]
  end

  it "finds drafts, which a normal site load leaves out" do
    load_fixture("classify").find("blog/hidden").should be_nil
    titles("draft=true").should eq ["Hidden"]
  end

  it "turns --drafts and --published into the draft filter" do
    Sage::Listing.status(false, false).should be_empty
    Sage::Listing.pages(ROOT, Sage::Listing.status(true, false)).map(&.title).should eq ["Hidden"]
    published = Sage::Listing.pages(ROOT, Sage::Listing.status(false, true)).map(&.title)
    published.size.should eq 11
    published.should_not contain "Hidden"
    expect_raises(Sage::Error, /exclude each other/) { Sage::Listing.status(true, true) }
    expect_raises(Sage::Error, /exclude each other/) { Sage::Listing.status(false, true, true) }
  end

  it "lists the pages created without a source file, by url, with --implicit" do
    Sage::Listing.status(false, false, true).should be_empty
    pages = Sage::Listing.pages(ROOT, implicit: true)
    pages.map(&.url).should eq ["/blog/", "/docs/", "/tags/a/", "/tags/b/", "/tags/cascaded/"]
    printed(pages).should start_with "/blog/\tBlog\n/docs/\tDocs\n/tags/a/\ta\n"
    printed(pages, paths: true).should start_with "/blog/\n/docs/\n"
    (pages.map(&.title) & Sage::Listing.pages(ROOT).map(&.title)).should be_empty
  end

  it "compares booleans and numbers as YAML reads them" do
    titles("draft=yes").should eq ["Hidden"]
    titles("draft=false").should be_empty
    titles("draft!=true").size.should eq 11
    titles("weight=5").should eq ["About"]
    titles("weight=5.0").should eq ["About"]
  end

  it "matches strings exactly, cascaded values included" do
    titles("title=About").should eq ["About"]
    titles("title=about").should be_empty
    titles("author=Section").should eq ["Child", "Section", "Silent"]
    titles("author=Site").size.should eq 9
  end

  it "matches a list by membership" do
    titles("tags=a").should eq ["Hello", "Later"]
    titles("tags=b").should eq ["Hello"]
    titles("tags=cascaded").should eq ["Child", "Section", "Silent"]
    titles("tags!=a").should_not contain("Later")
    titles("tags!=a").should contain("About")
  end

  it "matches dates by prefix" do
    titles("date=2026-01-02").should eq ["Hello"]
    titles("date=2026-01").should eq ["Hello", "Hidden", "Later", "Shortcodes"]
    titles("date=2025").should be_empty
  end

  it "tests whether a key is set" do
    titles("weight").should eq ["About"]
    titles("tags").should eq ["Hello", "Later", "Child", "Section", "Silent"]
    titles("tags!=").should eq titles("tags")
    titles("tags=").should eq ["About", "Hidden", "Shortcodes", "Custom", "Intro", "Home", "All tags"]
    titles("layout").should be_empty # reserved, though no page sets it
  end

  it "requires every filter to match" do
    titles("tags=a", "date=2026-01-05").should eq ["Later"]
    titles("draft=true", "tags=a").should be_empty
    titles("tags", "tags!=a").should eq ["Child", "Section", "Silent"]
  end

  it "prints path and title, or paths alone, relative to a directory" do
    pages = Sage::Listing.pages(ROOT, ["tags=a"])
    printed(pages).should eq "content/blog/hello/index.md\tHello\ncontent/blog/later.md\tLater\n"
    printed(pages, paths: true).should eq "content/blog/hello/index.md\ncontent/blog/later.md\n"
    printed(pages, nul: true).should eq "content/blog/hello/index.md\0content/blog/later.md\0"
  end

  it "rejects malformed filters and keys that no page has" do
    ["weight>5", "draft==true", "=true", "!draft", ""].each do |arg|
      expect_raises(Sage::Error, "bad filter #{arg.inspect}") { titles(arg) }
    end
    expect_raises(Sage::Error, %(no page has the front matter key "drfat")) { titles("drfat!=true") }
  end
end
