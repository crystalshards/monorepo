# Which of a repository's tags is the latest.
#
# Not the API's response order. GitHub does not document /tags as
# reverse-chronological, and a repository that retags an old release would
# quietly get the wrong default version if we trusted it. Not the commit date
# either, because dating every tag costs one core request per tag.
#
# So: semver where the tag is semver, which is nearly all of this corpus, and a
# documented fallback where it is not. The comparison is total and deterministic,
# so the same tag list always chooses the same latest.
module VersionOrder
  # A tag split into the parts semver compares, or nil when it is not a version
  # at all ("latest", "nightly", a date-stamped branch name).
  record Parsed,
    numbers : Array(Int32),
    prerelease : Array(String),
    original : String

  SEMVER = /\A[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[.-]([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?\z/

  def self.parse(tag : String) : Parsed?
    match = SEMVER.match(tag.strip)
    return nil unless match

    numbers = (1..3).compact_map { |index| match[index]?.try(&.to_i?) }
    return nil if numbers.empty?

    prerelease = match[4]?.try(&.split('.')) || [] of String

    Parsed.new(numbers, prerelease, tag)
  end

  # Newest first. Ties and unparseable tags keep their input order, so the
  # result is stable and a caller can rely on it.
  def self.sort(refs : Array(RepositorySnapshot::Ref)) : Array(RepositorySnapshot::Ref)
    indexed = refs.each_with_index.to_a

    indexed.sort! do |(left, left_index), (right, right_index)|
      comparison = compare(left, right)
      comparison.zero? ? left_index <=> right_index : comparison
    end

    indexed.map(&.[0])
  end

  # The version a page shows by default.
  #
  # A branch row only ever exists when there are no tags at all, so tags win
  # whenever there are any. Among tags, the highest release wins; a prerelease
  # is only chosen when nothing else has ever been released, because a shard
  # whose newest tag is 2.0.0-rc1 should still default to 1.9.0.
  def self.latest(refs : Array(RepositorySnapshot::Ref)) : RepositorySnapshot::Ref?
    tags = refs.select(&.tag?)
    return refs.first? if tags.empty?

    ordered = sort(tags)
    ordered.find { |ref| stable?(ref) } || ordered.first?
  end

  def self.stable?(ref : RepositorySnapshot::Ref) : Bool
    parsed = parse(ref.ref)
    return false unless parsed

    parsed.prerelease.empty?
  end

  # Negative when `left` is newer, so a plain sort puts newest first.
  private def self.compare(left : RepositorySnapshot::Ref, right : RepositorySnapshot::Ref) : Int32
    left_parsed = parse(left.ref)
    right_parsed = parse(right.ref)

    # A tag that is not a version sorts below every tag that is, rather than
    # being compared as a string against one.
    return 0 if left_parsed.nil? && right_parsed.nil?
    return 1 if left_parsed.nil?
    return -1 if right_parsed.nil?

    if (numbers = compare_numbers(left_parsed.numbers, right_parsed.numbers)) != 0
      return -numbers
    end

    -compare_prerelease(left_parsed.prerelease, right_parsed.prerelease)
  end

  # Missing components are zero, so 1.2 and 1.2.0 are the same version.
  private def self.compare_numbers(left : Array(Int32), right : Array(Int32)) : Int32
    size = Math.max(left.size, right.size)

    size.times do |index|
      comparison = (left[index]? || 0) <=> (right[index]? || 0)
      return comparison unless comparison.zero?
    end

    0
  end

  # Semver rule: a version with no prerelease outranks the same version with
  # one, so 1.0.0 is newer than 1.0.0-rc1.
  private def self.compare_prerelease(left : Array(String), right : Array(String)) : Int32
    return 0 if left.empty? && right.empty?
    return 1 if left.empty?
    return -1 if right.empty?

    size = Math.max(left.size, right.size)

    size.times do |index|
      left_part = left[index]?
      right_part = right[index]?

      return 1 if right_part.nil?
      return -1 if left_part.nil?

      left_number = left_part.to_i?
      right_number = right_part.to_i?

      comparison = if left_number && right_number
                     left_number <=> right_number
                   elsif left_number
                     # Numeric identifiers rank below alphanumeric ones.
                     -1
                   elsif right_number
                     1
                   else
                     left_part <=> right_part
                   end

      return comparison unless comparison.zero?
    end

    0
  end
end
