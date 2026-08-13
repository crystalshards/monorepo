module CrystalDocs
  # Version arithmetic for deciding which documented artifact a cross package
  # link should point at.
  #
  # This is deliberately separate from the database and the document store,
  # because the selection rule is the part that was wrong before and the part
  # worth testing on its own. String ordering is the specific trap: "1.10.0"
  # sorts before "1.9.0" lexically, so anything that compares version text
  # sends a reader on 1.10 to the 1.9 documentation. Segments are numbers here
  # and are compared as numbers.
  module Semver
    # A parsed version.
    #
    # Build metadata is dropped during parsing rather than stored: semver gives
    # it no part in precedence, and nothing on this site displays it.
    struct Version
      include Comparable(Version)

      getter major : Int32
      getter minor : Int32
      getter patch : Int32

      # Empty for a final release. Identifiers stay split apart because
      # precedence compares them one at a time, numerically where both sides
      # are numeric.
      getter prerelease : Array(String)

      def initialize(
        @major : Int32,
        @minor : Int32,
        @patch : Int32,
        @prerelease : Array(String) = [] of String,
      )
      end

      # Returns nil for anything that is not a version, which callers treat as
      # missing metadata rather than as a version that sorts low.
      def self.parse?(raw : String?) : Version?
        return nil if raw.nil?

        text = raw.strip
        text = text[1..] if text.starts_with?('v') || text.starts_with?('V')
        return nil if text.empty?

        text = text.split('+', 2).first
        core, _, pre = text.partition('-')

        segments = core.split('.')
        # Anything with a fourth segment is not a version this registry
        # publishes, and guessing at its meaning would be worse than no link.
        return nil if segments.size > 3

        numbers = [] of Int32
        segments.each do |segment|
          return nil if segment.empty?
          # `to_i?` would accept " 1" and "+1"; a version segment is digits.
          return nil unless segment.each_char.all?(&.ascii_number?)
          # Still `to_i?`, because a long enough digit run overflows Int32.
          number = segment.to_i?
          return nil unless number
          numbers << number
        end

        prerelease = pre.empty? ? [] of String : pre.split('.')
        return nil if prerelease.any?(&.empty?)

        new(numbers[0], numbers[1]? || 0, numbers[2]? || 0, prerelease)
      end

      def prerelease? : Bool
        !prerelease.empty?
      end

      def <=>(other : Version) : Int32
        comparison = major <=> other.major
        return comparison unless comparison.zero?

        comparison = minor <=> other.minor
        return comparison unless comparison.zero?

        comparison = patch <=> other.patch
        return comparison unless comparison.zero?

        compare_prerelease(other)
      end

      # A release outranks every prerelease of itself, so 1.0.0-rc1 < 1.0.0.
      private def compare_prerelease(other : Version) : Int32
        return 0 if prerelease.empty? && other.prerelease.empty?
        return 1 if prerelease.empty?
        return -1 if other.prerelease.empty?

        prerelease.each_with_index do |mine, index|
          theirs = other.prerelease[index]?
          # They ran out of identifiers first, so this version is the later
          # one: 1.0.0-rc.1 > 1.0.0-rc.
          return 1 if theirs.nil?

          comparison = compare_identifier(mine, theirs)
          return comparison unless comparison.zero?
        end

        prerelease.size <=> other.prerelease.size
      end

      private def compare_identifier(mine : String, theirs : String) : Int32
        mine_number = numeric_identifier(mine)
        theirs_number = numeric_identifier(theirs)

        if mine_number && theirs_number
          mine_number <=> theirs_number
        elsif mine_number
          # Numeric identifiers always rank below alphanumeric ones, so
          # 1.0.0-1 < 1.0.0-alpha.
          -1
        elsif theirs_number
          1
        else
          mine <=> theirs
        end
      end

      private def numeric_identifier(identifier : String) : Int32?
        return nil unless identifier.each_char.all?(&.ascii_number?)
        identifier.to_i?
      end

      def to_s(io : IO) : Nil
        io << major << '.' << minor << '.' << patch

        unless prerelease.empty?
          io << '-'
          prerelease.join(io, '.')
        end
      end
    end

    # A version requirement, as shard.yml writes one.
    #
    # Two registry columns are parsed by this: a dependency's
    # `version_requirement`, and a shard version's `crystal_version`, which is
    # the `crystal:` key copied out of shard.yml and is itself a requirement
    # rather than a single version.
    struct Requirement
      # One `<operator> <version>` term. A requirement is the conjunction of
      # its clauses, which is how shard.yml writes a range: ">= 2.0, < 3.0".
      record Clause, operator : String, version : Version

      # Two character operators are listed first so that ">=" is never read as
      # ">" followed by a version of "= 1.0.0".
      OPERATORS = {">=", "<=", "~>", ">", "<", "="}

      getter clauses : Array(Clause)

      def initialize(@clauses : Array(Clause))
      end

      # Returns nil when there is no requirement to honour, either because the
      # registry holds no value or because the value is not one we can read.
      # Callers treat that as missing metadata and leave the name plain.
      def self.parse?(raw : String?) : Requirement?
        return nil if raw.nil?

        text = raw.strip
        # A blank column is absent metadata rather than a statement about
        # versions, so it fails closed instead of accepting anything. Shards
        # records a deliberately unpinned dependency as "*", which is a
        # statement, and that one does accept any release.
        return nil if text.empty?
        return new([] of Clause) if text == "*"

        clauses = [] of Clause

        text.split(',').each do |term|
          parsed = clauses_for(term)
          return nil unless parsed
          clauses.concat(parsed)
        end

        new(clauses)
      end

      private def self.clauses_for(term : String) : Array(Clause)?
        text = term.strip
        return nil if text.empty?

        operator = OPERATORS.find { |candidate| text.starts_with?(candidate) }
        operand = operator ? text[operator.size..].strip : text

        return pessimistic_clauses(operand) if operator == "~>"

        version = Version.parse?(operand)
        return nil unless version

        # A bare version is an exact pin, which is also how the registry stores
        # a `crystal:` key written as a plain version.
        [Clause.new(operator || "=", version)]
      end

      # `~> 1.2.3` allows patch releases below 1.3.0; `~> 1.2` allows minor
      # releases below 2.0.0. The rule is to drop the last written segment and
      # raise the one that is now last, so the written precision carries the
      # whole meaning of the operator. It is read from the text, because the
      # parsed version has already filled in the segments that were left off.
      private def self.pessimistic_clauses(operand : String) : Array(Clause)?
        lower = Version.parse?(operand)
        return nil unless lower

        upper =
          if written_precision(operand) >= 3
            Version.new(lower.major, lower.minor + 1, 0)
          else
            Version.new(lower.major + 1, 0, 0)
          end

        [Clause.new(">=", lower), Clause.new("<", upper)]
      end

      private def self.written_precision(operand : String) : Int32
        text = operand.strip
        text = text[1..] if text.starts_with?('v') || text.starts_with?('V')
        text.split('+', 2).first.partition('-').first.split('.').size
      end

      def satisfied_by?(version : Version) : Bool
        # A prerelease is not a release. Letting 1.3.0-rc1 answer "~> 1.2"
        # would put a reader on documentation for an API that has not shipped,
        # so prereleases only count when the requirement asks for one.
        return false if version.prerelease? && !allows_prerelease?

        clauses.all? { |clause| satisfies?(clause, version) }
      end

      # The highest version that satisfies this requirement, or nil when none
      # does. Nil is a real answer and never means "use the newest instead".
      def best(versions : Enumerable(Version)) : Version?
        versions.select { |version| satisfied_by?(version) }.max?
      end

      # The lowest version this requirement can be satisfied by, or nil when
      # it names no lower bound at all, which "*" does not.
      #
      # This is the compiler era a shard is read against when no standard
      # library build exists to name a concrete one. A floor is the
      # conservative reading: a shard declaring ">= 1.12.0" is compiled by
      # anything from 1.12.0 upwards, so a dependency release needing more
      # than the floor cannot be shown to work for every reader of the page.
      #
      # ">" contributes its own version rather than the next one above it.
      # There is no next version to name, and a floor one release too low only
      # ever rejects more candidates, which is the safe direction.
      def floor : Version?
        best : Version? = nil

        clauses.each do |clause|
          next unless clause.operator.in?(">=", ">", "=")

          current = best
          best = clause.version if current.nil? || clause.version > current
        end

        best
      end

      private def allows_prerelease? : Bool
        clauses.any?(&.version.prerelease?)
      end

      private def satisfies?(clause : Clause, version : Version) : Bool
        case clause.operator
        when ">=" then version >= clause.version
        when "<=" then version <= clause.version
        when ">"  then version > clause.version
        when "<"  then version < clause.version
        else           version == clause.version
        end
      end
    end
  end
end
