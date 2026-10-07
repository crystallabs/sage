require "option_parser"

module Sage
  module CLI
    USAGE = <<-TEXT
      Usage: sage <command> [options]

      Commands:
        init DIR Create a new site skeleton in DIR
        build    Render the site into the output directory
        orphans  List output files that nothing in the site produces,
                 without building (-0: NUL-terminated, for xargs -0);
                 the same as diff --extra -l, --ignore included
        diff [--missing | --extra] [--ignore GLOB]... [--strict] [-l] [-0] [DIR]
                 Compare the files the site would produce with those under
                 DIR (default: the output directory), without building:
                 "+ path<TAB>origin" is not under DIR, "- path" is not
                 produced, "~ old<TAB>new" differ only in url spelling.
                 --missing or --extra list one side alone, as paths.
                 Exits 1 when anything was listed.
        pages [--drafts | --published | --implicit] [-l] [-0] [FILTER...]
                 List pages by front matter, drafts included, as
                 path<TAB>title (-l: paths only; -0: paths, NUL-terminated).
                 FILTER is key=value (equal, or a list containing value),
                 key!=value, key (set) or key= (not set); all must match.
                 --drafts lists only drafts, --published only the rest.
                 --implicit lists the pages a build creates without a
                 source file (taxonomies, terms, sections), as url<TAB>title
        serve    Build, serve locally, and rebuild on changes
                 (base_url defaults to the local address)
        hugo-convert [-w] FILE...
                 Translate Hugo shortcode calls to Jinja calls (stdout, or
                 with -w write FILE.j2 next to each FILE)
        version  Print version
      TEXT

    def self.run(argv = ARGV)
      root = Dir.current
      drafts = false
      published = false
      implicit = false
      clean = false
      touch = false
      base_url = nil
      nul = false
      paths = false
      port = 1313
      command = nil
      write = false
      files = [] of String
      side = nil
      ignore = [] of String
      strict = false

      parser = OptionParser.new do |p|
        p.banner = USAGE
        p.on("-s DIR", "--source DIR", "Site root (default: current directory)") { |d| root = File.expand_path(d) }
        p.on("-D", "--drafts", "Include draft pages (pages: list only drafts)") { drafts = true }
        p.on("-P", "--published", "pages: list only pages that are not drafts") { published = true }
        p.on("-I", "--implicit", "pages: list only pages created without a source file") { implicit = true }
        p.on("--clean", "Remove the output directory before building") { clean = true }
        p.on("--touch", "Update the mtime of unchanged output files too") { touch = true }
        p.on("-b URL", "--base-url URL", "Override base_url from config") { |u| base_url = u }
        p.on("-0", "--null", "orphans, pages, diff: paths only, NUL instead of newline") { nul = true }
        p.on("-l", "--paths", "pages, diff: print paths only, without titles or origins") { paths = true }
        p.on("--missing", "diff: only files the site would produce that DIR lacks") { side = :missing }
        p.on("--extra", "diff: only files under DIR that the site would not produce") { side = :extra }
        p.on("--ignore GLOB", "diff: leave out matching files (repeatable)") { |g| ignore << g }
        p.on("--strict", "diff: do not pair files that differ only in url spelling") { strict = true }
        p.on("-p PORT", "--port PORT", "Port for serve (default 1313)") { |v| port = v.to_i }
        p.on("-w", "--write", "hugo-convert: write FILE.j2 instead of printing") { write = true }
        p.on("-h", "--help", "Show help") { puts p; exit }
        p.unknown_args { |args| command = args.first?; files = args.size > 1 ? args[1..] : [] of String }
        p.invalid_option { |o| abort "unknown option #{o}\n#{p}" }
      end
      parser.parse(argv)

      case command
      when "init"
        Init.run(files.first? || abort("init: directory required"))
      when "build"           then Builder.build(root, drafts: drafts, clean: clean, touch: touch, base_url: base_url)
      when "orphans", "diff" then diff(root, command, files.first?, side, ignore, strict, paths, nul, drafts, base_url)
      when "pages"           then Listing.print(Listing.pages(root, Listing.status(drafts, published, implicit) + files, implicit), STDOUT, paths, nul)
      when "serve"           then Server.new(root, port, drafts, base_url).run
      when "hugo-convert"
        abort "hugo-convert: no files given" if files.empty?
        HugoConvert.run(files, write)
      when "version" then puts "sage #{VERSION}"
      else                abort parser.to_s
      end
    rescue e : Error
      abort "error: #{e.message}"
    end

    # `run`, but exiting quietly when `sage pages | head` closes stdout early.
    def self.main(argv = ARGV)
      run(argv)
    rescue e : IO::Error
      raise e unless e.os_error == Errno::EPIPE
      exit 1
    end

    # `orphans` is `diff --extra -l` of the output directory, except that
    # only `diff` exits 1 when the listing is not empty, like diff(1).
    private def self.diff(root, command, dir, side, ignore, strict, paths, nul, drafts, base_url)
      if command == "orphans"
        side, paths, dir = :extra, true, nil
      elsif nul && !side
        abort "diff: -0 needs --missing or --extra"
      end
      dir = File.expand_path(dir) if dir
      d = Builder.diff(root, dir, ignore, strict, drafts: drafts, base_url: base_url)
      shown = Builder.print_diff(d, STDOUT, side, paths, nul)
      exit 1 if shown && command == "diff"
    end
  end
end
