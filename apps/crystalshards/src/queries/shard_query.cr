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

  # Popularity is stars plus dependents, and there is deliberately no third
  # term. Nothing is downloaded from this registry: `shards` fetches from the
  # origin repository, so a download counter here can only ever read zero, and
  # ordering by it would just shuffle the list.
  #
  # Dependents leads. "Other indexed shards build on this" is a stronger claim
  # to being load-bearing than a star count, which accrues from visibility.
  # Stars break the tie, with unknown sorting LAST so a shard whose metadata
  # has never been fetched cannot outrank one we have actually measured.
  # updated_at makes the order total, which is what keeps pagination stable.
  def by_popularity
    self.order_by(ShardPopularity::DependentsOrder.new(:desc))
      .github_stars.desc_order(:nulls_last)
      .updated_at.desc_order
  end

  def by_dependents(direction : String? = nil)
    heading = direction == "asc" ? Avram::OrderBy::Direction::ASC : Avram::OrderBy::Direction::DESC

    self.order_by(ShardPopularity::DependentsOrder.new(heading))
      .github_stars.desc_order(:nulls_last)
  end

  # Every sort the listing offers, defined once. The action routes the `sort`
  # param straight through here rather than repeating this case, because the
  # two drifting apart is how "downloads" survived in one place after being
  # removed from the other.
  #
  # `direction` is an override, not a requirement: each sort key already
  # implies the only direction anyone wants from it. Names read A to Z, every
  # popularity signal reads highest first. That is why the default below is
  # per-key rather than a blanket "desc".
  def sort_by_column(column : String, direction : String? = nil)
    case column
    when "name"
      direction == "desc" ? name.desc_order : name.asc_order
    when "stars"
      if direction == "asc"
        github_stars.asc_order(:nulls_last).updated_at.desc_order
      else
        github_stars.desc_order(:nulls_last).updated_at.desc_order
      end
    when "dependents"
      by_dependents(direction)
    when "updated"
      direction == "asc" ? updated_at.asc_order : updated_at.desc_order
    else
      by_popularity
    end
  end

  def paginate(page : Int32, per_page : Int32 = 20)
    page = 1 if page < 1
    offset = (page - 1) * per_page
    self.offset(offset).limit(per_page)
  end
end
