require "./spec_helper"

describe Sage::Init do
  it "creates a site that builds" do
    dir = File.expand_path("out/init", __DIR__)
    FileUtils.rm_rf(dir)
    Sage::Init.run(dir)
    site = Sage::Builder.build(dir, log: IO::Memory.new)
    html = File.read(File.join(site.config.output_dir, "hello/index.html"))
    html.should contain "<h1>Hello</h1>"
    html.should contain %(<a href="/tags/first/">first</a>)
    File.exists?(File.join(site.config.output_dir, "css/style.css")).should be_true
    expect_raises(Sage::Error, /not empty/) { Sage::Init.run(dir) }
  end
end
