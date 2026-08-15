# Reduces a `shard.yml` `authors:` entry to a name safe to show a reader.
#
# shard.yml borrows RubyGems' "Name <email@example.com>" convention for one
# author per string, and the registry used to print that string whole on the
# shard page, which is a high traffic page. That hands a scraper a working
# address for free, and there is no safe partial fix: a mailto link still is
# the address, and obfuscating or reassembling it client side only slows down
# a scraper that runs the exact same parser this module does. So the address
# never reaches a rendered page or an API response, in any form, from
# anywhere that reads an author string. This is the one place in the app that
# parses one, so every caller goes through it instead of repeating the regex.
module AuthorIdentity
  # An address shaped run, wherever it sits in the entry. `authors:` is free
  # text and nothing validates it, so an address turns up outside angle
  # brackets as often as inside them, and "Jane jane@example.com" hands a
  # scraper exactly as much as "Jane <jane@example.com>" does. Matching the
  # run rather than a whole-string shape is what makes the removal total.
  EMAIL_PATTERN = /[^\s@<>()\[\],;]+@[^\s@<>()\[\],;]+/

  # The punctuation an address leaves behind once it is gone: the empty
  # bracket or paren pair that used to hold it. Left in place it renders as
  # "Jane <>" under an author heading, which reads as a rendering bug.
  LEFTOVER_PATTERN = /<\s*>|\(\s*\)|\[\s*\]/

  # What an author renders as when the entry carried no name of its own.
  # Deliberately not the local part of the address: "jane.smith" is still
  # half of a working address and a guessable domain recovers the rest, and
  # an entry that gave us only a mailbox never offered a name to publish.
  PLACEHOLDER = "unnamed author"

  # The display name for one `authors:` entry, with any address dropped.
  #
  # A plain name with no address passes through unchanged. Any address in the
  # entry is removed wherever it appears. An entry that was only an address
  # has no name left to show, so it renders as the placeholder and no part of
  # the address survives.
  def self.display_name(raw : String) : String
    entry = raw.strip
    return entry if entry.empty?

    name = tidy(entry.gsub(EMAIL_PATTERN, ""))
    name.empty? ? PLACEHOLDER : name
  end

  # Closes the gap the removal opened: the emptied brackets, the doubled
  # spaces, and a separator that was only ever there to hold the name and the
  # address apart. Internal punctuation is left alone, because "Doe, Jane" is
  # a name and not a leftover.
  private def self.tidy(text : String) : String
    text.gsub(LEFTOVER_PATTERN, " ")
      .gsub(/\s+/, " ")
      .strip
      .strip(" \t,;:-")
  end
end
