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
  # `Name <email>`. The name half is captured greedily up to the last "<...>"
  # pair, so a name that itself contains an angle bracket (shard.yml enforces
  # nothing about the shape of this field) still resolves at the real
  # address rather than at the first one.
  BRACKETED_PATTERN = /\A(.*)<\s*([^<>]*)\s*>\s*\z/

  # A bare address with no brackets and no name at all. shard.yml accepts
  # this too, because `authors:` is free text and nothing validates it.
  BARE_EMAIL_PATTERN = /\A[^\s@<>]+@[^\s@<>]+\z/

  # What an address-only author renders as once its address is gone and no
  # name was ever given to replace it.
  PLACEHOLDER = "unnamed author"

  # The display name for one `authors:` entry, with any address dropped.
  #
  # A plain name with no address passes through unchanged. A "Name <email>"
  # entry keeps the name. An entry that is only an address, bracketed or
  # bare, keeps the local part of the address: it still reads as an
  # identity, a handle rather than a mailbox, and it is never something a
  # scraper can mail.
  def self.display_name(raw : String) : String
    entry = raw.strip
    return entry if entry.empty?

    if match = BRACKETED_PATTERN.match(entry)
      name = match[1].strip
      return name unless name.empty?

      return local_part(match[2].strip)
    end

    return local_part(entry) if BARE_EMAIL_PATTERN.matches?(entry)

    entry
  end

  # The part of an address before the "@". An address so malformed that even
  # this is empty (a bare "<>", say) falls back to a neutral placeholder
  # rather than rendering an empty name under an "Author" heading.
  private def self.local_part(email : String) : String
    local = email.split('@', 2).first.strip
    local.empty? ? PLACEHOLDER : local
  end
end
