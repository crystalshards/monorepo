class SavePost < Post::SaveOperation
  permit_columns :title, :slug, :content, :excerpt, :author_name, :author_email,
    :tags, :published_at, :featured, :view_count

  before_save do
    validate_required title, content, author_name
    generate_slug_if_empty
    validate_required slug
    validate_slug_uniqueness
    generate_excerpt_if_empty
  end

  private def generate_slug_if_empty
    if slug.value.nil? || slug.value.to_s.strip.empty?
      slug.value = title.value.to_s.downcase
        .gsub(/[^a-z0-9\s-]/, "")
        .gsub(/\s+/, "-")
        .gsub(/-+/, "-")
        .strip("-")
    end
  end

  private def validate_slug_uniqueness
    return if slug.value.nil?

    query = PostQuery.new.slug(slug.value.not_nil!)
    if record
      query = query.id.not.eq(record.not_nil!.id)
    end

    if query.any?
      slug.add_error("has already been taken")
    end
  end

  private def generate_excerpt_if_empty
    if excerpt.value.nil? || excerpt.value.to_s.strip.empty?
      content_text = content.value.to_s
      excerpt.value = content_text[0...200] + (content_text.size > 200 ? "..." : "")
    end
  end
end
