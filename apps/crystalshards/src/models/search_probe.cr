# One search term this registry has taken to GitHub, and what came back.
#
# The row is a claim first and a record second. Its whole reason for existing is
# that GitHub's code search allows 10 requests a minute and the thing that
# triggers a probe is a visitor typing into a search box, so "has anybody
# already asked this" has to be answerable before a page load spends anything.
class SearchProbe < BaseModel
  table do
    column term : String
    column probed_at : Time
    column hits : Int32?
    column registered : Int32?
    column last_error : String?
  end

  # The one spelling of a term this registry stores.
  #
  # Case and surrounding whitespace are not part of what somebody meant, and
  # internal runs of whitespace are a typo rather than a distinction. Folding
  # them here is what makes the unique index on `term` a real answer to "has
  # this been asked", instead of one that three formattings of the same word
  # walk straight past.
  def self.normalize(term : String) : String
    term.strip.downcase.gsub(/\s+/, " ")
  end
end
