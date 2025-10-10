class ShardQuery < Shard::BaseQuery
  def search(term : String?)
    return self if term.nil? || term.empty?

    where do |q|
      q.name.ilike("%#{term}%")
        .or(&.description.ilike("%#{term}%"))
    end
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
