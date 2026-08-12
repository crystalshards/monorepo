module CrystalDocs
  # Turns a type name into a link.
  #
  # Documentation is only useful if the names in it are reachable. A signature
  # mentioning `HTTP::Server::Context` should get the reader to that type,
  # whether it lives in this package, in another shard we index, or in the
  # Crystal standard library.
  #
  # The standard library is not a special case: it is published through the
  # same pipeline as every shard, as the package named by `CORE_PACKAGE`, so
  # core types resolve to pages on this site rather than sending the reader
  # somewhere else. That also removes the guesswork an external link needed.
  # An earlier version kept an allowlist of standard library constants and
  # pointed at crystal-lang.org, which meant deciding from the shape of a name
  # whether a page existed. Now the index either contains the type or it does
  # not, and an unresolved name stays plain text, because a link that guesses
  # sends the reader to a 404 and implies the name means something it does not.
  class TypeLinker
    # Names the compiler emits that are not types a reader can follow.
    NON_TYPES = Set{"self", "nil", "Nil", "Void", "NoReturn", "_"}

    def initialize(
      @package_name : String,
      @version : String,
      @local_types : Set(String),
      @dependency_index : Hash(String, DependencyIndex::Location) = {} of String => DependencyIndex::Location,
    )
    end

    # The set of names this package defines, so everything else is known to
    # come from somewhere else. Indexed without generic parameters, matching
    # how names appear in signatures.
    def self.local_names(document : DocsDocument) : Set(String)
      names = Set(String).new
      document.all_types.each { |type| names << type.qualified_name }
      names
    end

    record Link, href : String, external : Bool, title : String?

    # Returns nil when the name should be rendered as plain text.
    def link_for(type_name : String) : Link?
      name = normalize(type_name)
      return nil if name.empty? || NON_TYPES.includes?(name)

      if @local_types.includes?(name)
        Link.new(
          href: PackagePaths.type_path(@package_name, @version, name.gsub("::", "/")),
          external: false,
          title: nil
        )
      elsif owner = @dependency_index[name]?
        Link.new(
          href: PackagePaths.type_path(owner[:package], owner[:version], name.gsub("::", "/")),
          # Still on this site, but a different package than the one being
          # read, which is worth marking so the reader knows they are moving.
          external: true,
          title: title_for(name, owner)
        )
      end
    end

    private def title_for(name : String, owner : DependencyIndex::Location) : String
      if owner[:package] == CORE_PACKAGE
        # The standard library version is chosen from what the package being
        # read declared support for, not from what is current, so naming it
        # tells the reader which era of the API they are about to look at.
        "#{name} in the Crystal standard library #{owner[:version]}"
      else
        "#{name} in #{owner[:package]} #{owner[:version]}"
      end
    end

    # Generics, unions and nilable shorthand decorate the name; strip the
    # decoration so `Array(String)?` resolves as `Array`.
    private def normalize(type_name : String) : String
      name = type_name.strip
      name = name.split('(').first
      name = name.split('|').first.strip
      name = name.rchop('?')
      name.strip
    end
  end
end
