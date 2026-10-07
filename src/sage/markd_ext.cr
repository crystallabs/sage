require "markd"
require "tartrazine"

# markd highlights fenced code through Tartrazine whenever Tartrazine is
# loaded, and raises on unknown languages. Make both configurable: a nil
# formatter renders plain <pre><code>, and an unknown language falls back to
# plain text rather than failing the build.
class Markd::HTMLRenderer
  private def render_code_block_use_tartrazine(node : Node, formatter : Tartrazine::Formatter?)
    languages = node.fence_language ? node.fence_language.split : nil
    lang = code_block_language(languages)
    newline

    lexer = if lang && formatter
              begin
                Tartrazine.lexer(lang)
              rescue Tartrazine::UnknownLexerError
                nil
              end
            end

    if lexer && formatter
      literal(formatter.format(node.text.chomp, lexer))
    else
      # Same markup as markd without Tartrazine, language class included.
      code_tag_attrs = attrs(node)
      if lang
        code_tag_attrs ||= {} of String => String
        code_tag_attrs["class"] = "language-#{escape(lang)}"
      end
      pre_tag_attrs = @options.prettyprint? ? {"class" => "prettyprint"} : nil
      tag("pre", pre_tag_attrs) do
        tag("code", code_tag_attrs) do
          code_block_body(node, lang)
        end
      end
      newline
    end
  end
end

# markd takes everything from a `&` up to the next `;` in the paragraph as an
# entity reference, so "AT&T ... [link](x) ...; ..." loses every piece of
# inline markup in between. Only accept what has the form of an entity.
class Markd::Parser::Inline
  private def entity(node : Node)
    return false unless char_at?(@pos) == '&'
    raw = match(Rule::NUMERIC_HTML_ENTITY) || match(Rule::HTML_ENTITY) || return false
    node.append_child(text(HTML.decode_entity(raw.byte_slice(1, raw.bytesize - 2))))
    true
  end

  # GFM's bare autolinks (www., http://, ...) are only recognized at the start
  # of a line, after whitespace, or after one of `*_~(`. markd checks that
  # when scanning text but not here, so the url in `<a href="u">u</a>` was
  # linked a second time, taking the `<` of `</a>` with it.
  private def auto_link(node : Node)
    return false if char_at?(@pos) != '<' && @pos > 0 && !"*_~( \n\t".includes?(char_at(@pos - 1))
    previous_def
  end
end
