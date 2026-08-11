class ShardQuery < Shard::BaseQuery
  # Search matches the display name, the description and the canonical slug,
  # so "router" finds every shard called router on every host and
  # "gitlab.com/acme" finds that owner's shards. Two shards sharing a name
  # both match: neither can shadow the other, because the name was never the
  # thing that made them distinct.
  def search(term : String?)
    return self if term.nil? || term.empty?

    where do |q|
      q.name.ilike("%#{term}%")
        .or(&.description.ilike("%#{term}%"))
        .or(&.canonical_slug.ilike("%#{term}%"))
    end
  end

  # Resolves the key carried by a URL path, an API path or a queue payload.
  #
  # A canonical slug ("github.com/kemalcr/kemal") is matched exactly. A bare
  # name is honoured only when exactly one shard answers to it: with two
  # "router" shards there is no correct answer, and returning either would
  # silently show, index or document the wrong repository. nil therefore means
  # "no single shard is meant here", which callers turn into a 404 or a failed
  # job rather than a guess.
  def resolve(key : String) : Shard?
    return nil if key.empty?

    if shard = clone.canonical_slug(key).first?
      return shard
    end

    # Only a bare name can fall through; anything carrying a separator was
    # meant to be a slug and simply does not exist.
    return nil if key.includes?('/')

    matches = clone.name(key).limit(2).to_a
    matches.size == 1 ? matches.first : nil
  end

  # True when a bare name names more than one shard, which is what the legacy
  # single-segment URLs have to disambiguate.
  def ambiguous_name?(value : String) : Bool
    clone.name(value).limit(2).to_a.size > 1
  end

  def by_license(license : String?)
    return self if license.nil? || license.empty?

    self.license(license)
  end

  def with_min_stars(min_stars : Int32?)
    return self if min_stars.nil?

    github_stars.gte(min_stars)
  end

  def sort_by_column(column : String, direction : String = "desc")
    case column
    when "name"
      direction == "asc" ? name.asc_order : name.desc_order
    when "downloads"
      direction == "asc" ? total_downloads.asc_order : total_downloads.desc_order
    when "stars"
      direction == "asc" ? github_stars.asc_order : github_stars.desc_order
    when "updated"
      direction == "asc" ? updated_at.asc_order : updated_at.desc_order
    else
      updated_at.desc_order
    end
  end

  def paginate(page : Int32, per_page : Int32 = 20)
    page = 1 if page < 1
    offset = (page - 1) * per_page
    self.offset(offset).limit(per_page)
  end
end
