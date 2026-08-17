module CrystalDocs
  # Every version of a package this site can name, not only the ones it has
  # built.
  #
  # The switcher used to read `doc_versions`, which is build state rather than
  # a catalogue. A row only appears there once somebody has asked for that
  # version, so a package with sixty tags and two visits offered a reader a
  # choice of two, and there was no way to reach the other fifty-eight except
  # by typing a URL. The registry already holds them.
  #
  # Listing an unbuilt version is not a dead link on this site. Documentation
  # is built on demand: asking for a version registers it and enqueues the
  # build, which is exactly what `Docs::VersionRendering` does with any version
  # whose artifact is missing. The switcher is simply the honest way to reach
  # that, instead of leaving it to readers who guess the URL shape.
  #
  # Ordering is semver and descending. `sort_by(&.version)` is a string sort,
  # which puts 1.9.0 above 1.10.0; `Semver` exists in this app because that
  # exact mistake sent readers to the wrong documentation once already.
  module VersionCatalogue
    # What this site can currently say about one version.
    #
    # `Unbuilt` is the new one, and it is a different fact from `Building`: the
    # registry has published it and nobody has ever asked us for it, so no
    # build has been attempted and none is queued.
    enum State
      Built
      Building
      Failed
      Unbuilt
    end

    record Entry, version : String, state : State do
      def built? : Bool
        state.built?
      end
    end

    def self.for(doc : Doc) : Array(Entry)
      entries = {} of String => Entry

      doc.doc_versions.each do |doc_version|
        entries[doc_version.version] =
          Entry.new(doc_version.version, state_for(doc_version.build_status))
      end

      # A registry row never overwrites a local one. Local build state is the
      # more specific answer and the registry has nothing to say about it: the
      # registry knows a version was published, not whether we rendered it.
      published_versions(doc.package_name).each do |version|
        entries[version] ||= Entry.new(version, State::Unbuilt)
      end

      sorted(entries.values)
    end

    private def self.state_for(build_status : String?) : State
      case build_status
      when "success" then State::Built
      when "failed"  then State::Failed
      else                State::Building
      end
    end

    # The registry is a separate database reached over the network, and this
    # runs while rendering a page. Losing it costs a reader the versions we
    # have never built, which is a smaller failure than losing the page: the
    # local rows are still a correct answer, just a shorter one. Logged rather
    # than swallowed, because a registry that is down for a week should be
    # visible to whoever reads the logs.
    private def self.published_versions(package_name : String) : Array(String)
      RegistryMetadata.build
        .published_versions([package_name])
        .fetch(package_name) { [] of RegistryMetadata::PublishedVersion }
        .map(&.version)
    rescue ex
      Log.for("crystaldocs.version_catalogue").warn(exception: ex) do
        "registry unreachable while listing versions for #{package_name}; " \
        "showing only versions this site has rows for"
      end
      [] of String
    end

    # Newest first. Anything that does not parse as a version sorts below
    # everything that does, rather than being dropped: it is still a row we
    # hold, and a reader looking for it should find it at the bottom instead of
    # concluding it is gone.
    private def self.sorted(entries : Array(Entry)) : Array(Entry)
      entries.sort do |left, right|
        parsed_left = Semver::Version.parse?(left.version)
        parsed_right = Semver::Version.parse?(right.version)

        if parsed_left && parsed_right
          parsed_right <=> parsed_left
        elsif parsed_left
          -1
        elsif parsed_right
          1
        else
          right.version <=> left.version
        end
      end
    end
  end
end
