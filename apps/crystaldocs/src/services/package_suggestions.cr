module CrystalDocs
  # What the masthead field offers while the reader is still typing.
  #
  # The same source the browse page draws from, and that is the point. This
  # site's catalogue is the registry's list of shards, not the `docs` rows this
  # app happens to have built, so a suggestion list read from `docs` would
  # offer only packages somebody had already opened here. `PackageCatalogue`
  # settles that question for the page; this settles it the same way for the
  # field above it.
  #
  # What it deliberately does not do is join local build state. `page` does,
  # because a card shows whether documentation exists, and it costs a scan of
  # every built package to work out the ordering. A suggestion list runs on
  # keystrokes and shows a name, so it pays for neither. The link it hands
  # back is the package's ordinary URL, which registers the package and
  # commissions a build the first time it is visited, exactly as a card's does.
  module PackageSuggestions
    # One offer: what to show, and where it goes.
    record Suggestion,
      name : String,
      # The repository, or nil for a package that has none. Shown under the
      # name so two shards publishing under one name are told apart; nil for
      # the standard library and the rows predating host qualified identity,
      # which have nothing to qualify.
      repository : String?,
      path : String

    # Two characters. One is not a guess about anything: it prefixes a large
    # fraction of the registry, and the eight rows the ordering happens to pick
    # are noise dressed as help. It also spares both databases a query for the
    # keystroke that begins every search.
    MINIMUM_TERM = 2

    # Eight rows: scannable without scrolling, readable under the field at a
    # phone width, and a hard ceiling on what one keystroke can cost.
    LIMIT = 8

    def self.for(term : String?, limit : Int32 = LIMIT) : Array(Suggestion)
      stripped = term.try(&.strip)
      return [] of Suggestion unless stripped && stripped.size >= MINIMUM_TERM

      RegistryPackages.build.suggest(stripped, limit).map do |suggestion|
        key = suggestion.key

        Suggestion.new(
          name: suggestion.name,
          repository: suggestion.slug,
          path: PackagePaths.package_path(key),
        )
      end
    end
  end
end
