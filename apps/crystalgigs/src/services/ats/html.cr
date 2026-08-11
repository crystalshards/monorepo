require "html"

module CrystalGigs
  module Ats
    # Turns ATS-supplied description markup into plain text.
    #
    # Job descriptions are rendered through `raw` on the job page, so anything
    # arriving from a third party has to be inert before it is stored. The
    # guarantee this module makes is deliberately blunt and easy to verify:
    # **the returned string contains no `<` and no `>`**, whatever was fed in,
    # including payloads that were escaped more than once. Structure survives
    # as newlines and list dashes.
    module Html
      LIST_ITEM = /<\s*li[^>]*>/i
      # `li` is absent on purpose: LIST_ITEM already opens each item, and
      # treating `</li>` as a block break would put a blank line between
      # every bullet.
      BLOCK   = /<\s*\/?\s*(?:p|div|br|hr|h[1-6]|ul|ol|table|tr|section|article|header|footer|blockquote|pre)[^>]*>/i
      ANY_TAG = /<[^>]*>/

      def self.to_text(markup : String?) : String
        return "" if markup.nil?

        # Pass one: providers ship HTML inside JSON strings with the markup
        # itself entity-escaped (Greenhouse does exactly this).
        text = ::HTML.unescape(markup)
        text = text.gsub(LIST_ITEM, "\n- ")
        text = text.gsub(BLOCK, "\n")
        text = text.gsub(ANY_TAG, " ")
        # Pass two: entities that were inside the markup's text nodes.
        text = ::HTML.unescape(text)
        # Anything still bracket-shaped was multiply escaped. Strip the
        # brackets so no markup can reach a template, escaped or not.
        text = text.delete("<>")
        collapse(text)
      end

      # Joins markup fragments into one plain-text body, dropping the blanks
      # and separating what is left with a blank line.
      def self.join_all(fragments : Enumerable(String?)) : String
        fragments
          .map { |fragment| to_text(fragment) }
          .reject(&.blank?)
          .join("\n\n")
      end

      private def self.collapse(text : String) : String
        lines = text.gsub('\u00A0', ' ').split('\n').map do |line|
          line.gsub(/[ \t]+/, " ").strip
        end

        result = String.build do |io|
          blanks = 0
          wrote_any = false
          lines.each do |line|
            if line.empty?
              blanks += 1
              next
            end
            # One newline between adjacent lines, two where the markup had a
            # real break, never more.
            io << (blanks.zero? ? "\n" : "\n\n") if wrote_any
            blanks = 0
            wrote_any = true
            io << line
          end
        end

        result.strip
      end
    end
  end
end
