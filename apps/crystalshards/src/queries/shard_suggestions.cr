# What the masthead field offers while the reader is still typing.
#
# A different question from `ShardQuery#search`, and answered differently on
# purpose. The search behind the Enter key matches anywhere in the name, the
# description or the slug, because a reader who has committed to a search wants
# everything related to the word. A suggestion list runs on keystrokes, so it
# matches only prefixes: it is guessing at a name the reader already has in
# mind and is part way through spelling, and an infix match on two characters
# offers most of the registry.
#
# That also makes it answerable from an index. Prefixes on `lower(name)` and
# `lower(canonical_slug)` are served by the two expression indexes migration 17
# adds; an infix match is served by nothing this schema has.
#
# Suggestions are therefore always a subset of what the search page returns for
# the same term, never something it would not show.
module ShardSuggestions
  # One offer: a shard's display name, and where it lives.
  record Suggestion, name : String, slug : String?, path : String

  # Two characters. One is not a guess about anything: on this registry "c"
  # prefixes hundreds of shards, and the eight the ordering happens to pick are
  # noise dressed as help. It also spares the database a query for the
  # keystroke that starts every search.
  MINIMUM_TERM = 2

  # Eight rows. The list has to be scannable without scrolling and readable
  # under the field at a phone width, and the cost per keystroke is bounded by
  # this number rather than by how many shards match.
  LIMIT = 8

  # Ordered by stars, then name, then id.
  #
  # Stars rather than the dependent count `ShardQuery#by_popularity` leads
  # with. Dependents is the stronger signal and it is a correlated count per
  # row, which is a fair price for one browse page and not one to pay on every
  # keystroke. NULLS LAST for the same reason that query gives: an unmeasured
  # shard must not outrank a measured one just by being unknown.
  #
  # Name then id after it, so the order is total. Most rows have no star count
  # at all, so without both tiebreakers a page of ties could come back in a
  # different order on two consecutive keystrokes and the list would reshuffle
  # under the reader's arrow keys.
  SQL = <<-SQL
    SELECT shards.name, shards.canonical_slug
    FROM shards
    WHERE lower(shards.name) LIKE $1
       OR lower(shards.canonical_slug) LIKE $1
    ORDER BY shards.github_stars DESC NULLS LAST, shards.name ASC, shards.id ASC
    LIMIT $2
    SQL

  def self.for(term : String?, limit : Int32 = LIMIT) : Array(Suggestion)
    pattern = prefix_pattern(term)
    return [] of Suggestion unless pattern

    AppDatabase.query_all(SQL, pattern, limit, as: {String, String?}, queryable: "ShardSuggestions")
      .map do |(name, slug)|
        Suggestion.new(name: name, slug: slug, path: Shard.url_path(name, slug))
      end
  end

  # The bound parameter, or nil when there is nothing worth asking.
  #
  # Lowercased here because the index holds `lower(...)`: a pattern with a
  # capital in it would match nothing rather than falling back to a scan, so
  # this is correctness and not just cost.
  #
  # `%` and `_` are escaped because they are LIKE's own wildcards. A reader
  # typing "%" would otherwise match every shard, which is both wrong and the
  # one input that turns this into a full scan. The backslash goes first or it
  # would escape the escapes.
  private def self.prefix_pattern(term : String?) : String?
    return nil unless term

    stripped = term.strip
    return nil if stripped.size < MINIMUM_TERM

    escaped = stripped.downcase
      .gsub("\\", "\\\\")
      .gsub("%", "\\%")
      .gsub("_", "\\_")

    "#{escaped}%"
  end
end
