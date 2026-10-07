require "spec"
require "json"
require "../src/sage"

FIXTURES = File.expand_path("fixtures", __DIR__)
EXAMPLE  = File.expand_path("../example", __DIR__)
MINIMA   = File.expand_path("../themes/minima/exampleSite", __DIR__)

def load_fixture(name : String, drafts = false) : Sage::Site
  Sage::Site.new(Sage::Config.load(File.join(FIXTURES, name)), drafts: drafts)
end
