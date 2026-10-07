require "yaml"

module SSG
  # `ssg pages [FILTER...]`: the pages that have a source file, selected by
  # front matter. Computed from the site graph; nothing is rendered or written.
  module Listing
    # One command-line filter, matched against a page's effective front
    # matter, which includes cascaded defaults:
    #
    #   key=value    the key equals value, or is a list containing it
    #   key!=value   the opposite, so pages without the key match too
    #   key          the key is set
    #   key=         the key is not set: absent, null, "" or []
    record Filter, key : String, value : String, negate : Bool do
      SYNTAX = /\A([\w.-]+)(?:(!?=)(.*))?\z/m

      def self.parse(arg : String) : Filter
        m = SYNTAX.match(arg)
        if m.nil? || m[3]?.try(&.starts_with?('='))
          raise Error.new("bad filter #{arg.inspect}: expected key=value, key!=value, key or key=")
        end
        # A bare key reads as `key!=`: not unset.
        new(m[1], m[3]? || "", m[2]? != "=")
      end

      def matches?(page : Page) : Bool
        raw = page.data[key]?.try(&.raw)
        (value.empty? ? unset?(raw) : holds?(raw)) != negate
      end

      private def unset?(raw) : Bool
        case raw
        when Nil                 then true
        when String, Array, Hash then raw.empty?
        else                          false
        end
      end

      # Strings compare exactly. Booleans and numbers compare as YAML would
      # read the value, so `draft=true` finds `draft: yes`. A date matches
      # any prefix of its RFC 3339 form: `date=2024`, `date=2024-03-01`.
      private def holds?(raw) : Bool
        case raw
        when Array                then raw.any? { |v| holds?(v.raw) }
        when String               then raw == value
        when Time                 then raw.to_rfc3339.starts_with?(value)
        when Bool, Int64, Float64 then raw.to_s == value || raw == YAML::Schema::Core.parse_scalar(value)
        else                           false
        end
      end
    end

    # Keys a filter may name even when no page happens to set them.
    RESERVED = %w[title date draft weight slug url aliases layout paginate outputs cascade]

    # Pages matching every filter. Normally these are the pages that have a
    # source file, drafts included, ordered by source path. With *implicit*
    # they are the pages a build creates without one (implicit sections,
    # taxonomy indexes and terms), ordered by url; drafts are then left out
    # as in a build, because they decide which of these pages exist.
    def self.pages(root : String, args : Array(String) = [] of String, implicit : Bool = false) : Array(Page)
      filters = args.map { |a| Filter.parse(a) }
      site = Site.new(Config.load(root), drafts: !implicit)
      pages = site.pages.select { |p| p.synthetic? == implicit }
      known = RESERVED + site.config.taxonomies
      filters.each do |f|
        next if known.includes?(f.key) || pages.any?(&.data.has_key?(f.key))
        raise Error.new("no page has the front matter key #{f.key.inspect}")
      end
      pages.select { |p| filters.all?(&.matches?(p)) }.sort_by! { |p| source(p) }
    end

    # The filter behind `--drafts` (only drafts) and `--published` (only
    # the rest); none when neither is given, and none for `--implicit`,
    # which selects another set of pages altogether. At most one of the
    # three may be given.
    def self.status(drafts : Bool, published : Bool, implicit : Bool = false) : Array(String)
      if {drafts, published, implicit}.count(true) > 1
        raise Error.new("pages: --drafts, --published and --implicit exclude each other")
      end
      return ["draft=true"] if drafts
      published ? ["draft!=true"] : [] of String
    end

    # The file a page's front matter comes from; the url of a page that
    # has no file.
    def self.source(page : Page) : String
      return page.url if page.synthetic?
      (page.variants.find { |v| v.resolved.format == "html" } || page.variants.first).source_path
    end

    # `path<TAB>title` per line, with paths relative to *base*; a page
    # without a source file shows its url instead. Only the path when
    # *paths* is set or with *nul*, which ends each with NUL for `xargs -0`.
    def self.print(pages : Array(Page), io : IO, paths : Bool = false, nul : Bool = false, base : String = Dir.current)
      pages.each do |p|
        io << (p.synthetic? ? p.url : Path[source(p)].relative_to(base))
        io << '\t' << p.title.gsub(/\s+/, ' ') unless paths || nul
        io << (nul ? '\0' : '\n')
      end
    end
  end
end
