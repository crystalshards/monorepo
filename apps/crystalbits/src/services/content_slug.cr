module ContentSlug
  MAX_LENGTH = 80

  # Slugs are unique in the database, so generation has to settle collisions
  # rather than hand the caller a value that will fail on insert. Two posts
  # called "Crystal 1.21.0 is released" become ...released and ...released-2.
  def self.generate(title : String) : String
    base = normalize(title)
    base = "item" if base.empty?

    candidate = base
    suffix = 2

    while ContentItemQuery.new.slug(candidate).any?
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end

    candidate
  end

  def self.normalize(title : String) : String
    title.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')[0, MAX_LENGTH].strip('-')
  end
end
