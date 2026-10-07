module SSG
  module Builder
    def self.renderer(root : String, drafts : Bool = false, base_url : String? = nil, touch : Bool = false) : Renderer
      config = Config.load(root)
      config.base_url = base_url if base_url
      site = Site.new(config, drafts: drafts)
      Renderer.new(site, TemplateEnv.build(site), touch: touch)
    end

    # One full build: load site, render everything.
    def self.build(root : String, drafts : Bool = false, clean : Bool = false, touch : Bool = false,
                   base_url : String? = nil, log : IO = STDERR) : Site
      r = renderer(root, drafts, base_url, touch)
      FileUtils.rm_rf(r.output_dir) if clean && Dir.exists?(r.output_dir)
      total = r.build
      log.puts "#{r.site.pages.size} pages, #{total} files in #{r.output_dir}: #{r.changed} written, #{r.unchanged} unchanged#{touch ? " (touched)" : ""}"
      r.site
    end

    # Files in the output directory that the site would not produce.
    # Computed from the site graph; nothing is rendered or written.
    def self.orphans(root : String, drafts : Bool = false, base_url : String? = nil) : Array(String)
      renderer(root, drafts, base_url).orphans
    end

    # The plan against the files under *dir*, the output directory when
    # nil. Nothing is rendered or written.
    def self.diff(root : String, dir : String? = nil, ignore : Array(String) = [] of String, strict : Bool = false,
                  drafts : Bool = false, base_url : String? = nil) : Renderer::Diff
      r = renderer(root, drafts, base_url)
      r.diff(dir || r.output_dir, ignore, strict)
    end

    # One line per difference, sorted by path relative to the compared
    # directory: `+ path<TAB>origin` for a planned file not there, `- path`
    # for a file there that the site would not produce, and
    # `~ old<TAB>new` for a pair that differ only in url spelling. With
    # *side* (`:missing` or `:extra`) just that side's paths, unprefixed,
    # relative to *base* so that the shell can use them, and
    # NUL-terminated with *nul*. *paths* drops the origin column.
    # Returns whether anything was printed.
    def self.print_diff(d : Renderer::Diff, io : IO, side : Symbol? = nil, paths : Bool = false,
                        nul : Bool = false, base : String = Dir.current) : Bool
      sep = nul ? '\0' : '\n'
      shell = ->(rel : String) { Path[File.join(d.dir, rel)].relative_to(base).to_s }
      origin = ->(j : Renderer::Job) { paths || nul ? "" : "\t#{origin(j, base)}" }
      case side
      when :missing
        d.missing.each { |j| io << shell.call(j.rel) << origin.call(j) << sep }
        !d.missing.empty?
      when :extra
        d.extra.each { |r| io << shell.call(r) << sep }
        !d.extra.empty?
      else
        old = d.renamed.map { |r, _| r }.to_set
        new = d.renamed.map { |_, j| j.rel }.to_set
        lines = [] of {String, String}
        d.missing.each { |j| lines << {j.rel, "+ #{j.rel}#{origin.call(j)}"} unless new.includes?(j.rel) }
        d.extra.each { |r| lines << {r, "- #{r}"} unless old.includes?(r) }
        d.renamed.each { |r, j| lines << {j.rel, "~ #{r}\t#{j.rel}"} }
        lines.sort_by!(&.[0]).each { |_, l| io << l << sep }
        !lines.empty?
      end
    end

    # A job's origin for display: source files relative to *base*, the
    # rest (`list /tags/`, `alias /old/ of blog/new`) as is.
    private def self.origin(j : Renderer::Job, base : String) : String
      j.origin.starts_with?('/') && File.exists?(j.origin) ? Path[j.origin].relative_to(base).to_s : j.origin
    end
  end
end
