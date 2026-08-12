require "../../services/stored_manifest"

# One shard, at one version.
#
# The registry's problem was never layout, it was that a page could be reached
# and say nothing. So the rule here is that every absence is rendered as a
# statement: no tags, no README, no description, no licence, no manifest for
# the selected version, no successful index at all. Most of the registry is
# minimal repositories, which makes sparse the normal case, and a normal case
# has to look deliberate rather than broken.
#
# Downloads are deliberately absent. Nothing is downloaded from us, `shards`
# fetches from the origin repository, so the figure could only ever be zero
# and a permanent zero reads as "nobody uses this". Popularity here is stars
# and dependents.
class Shards::ShowPage < MainLayout
  needs shard : Shard
  # Newest first. The same order the picker uses, because two orderings of one
  # list is how a page ends up disagreeing with itself.
  needs versions : Array(ShardVersion)
  needs selected_version : ShardVersion?
  # Dependency rows for the selected version, with resolved targets preloaded.
  needs dependencies : Array(Dependency)
  # The parsed shard.yml at the selected version. nil means nothing is indexed
  # for it, which is a statement the page makes rather than a blank it draws.
  needs manifest : StoredManifest?
  needs dependent_count : Int32
  needs dependents : Array(Shard)

  def page_title
    if version = @selected_version
      "#{@shard.name} #{version.version}"
    else
      @shard.name
    end
  end

  def content
    section class: "section" do
      render_header
      div class: "shard-content" do
        div class: "shard-main" do
          render_index_notices
          render_installation
          render_manifest_section
          render_dependencies_section
          render_readme_section
        end

        div class: "shard-sidebar" do
          render_links
          render_selected_version_section
          render_dependents_section
          render_repository_section
          render_registry_section
        end
      end
    end
  end

  # ---- header --------------------------------------------------------------

  private def render_header
    div class: "shard-header" do
      div class: "shard-title-block" do
        h1 class: "shard-title" do
          text @shard.name
        end

        mount VersionSelector,
          shard: @shard,
          versions: @versions,
          selected: @selected_version
      end

      # Two shards can share a name, so the repository is part of the title,
      # not a footnote. It is what tells a reader which "router" this is.
      para class: "shard-identity" do
        text @shard.canonical_slug || @shard.repository_url
      end

      if description = @shard.description
        para class: "shard-description-large" do
          text description
        end
      else
        para class: "shard-description-large text-muted" do
          text "No description declared in shard.yml."
        end
      end

      render_stats
    end
  end

  # Stars and dependents, and nothing that cannot be true.
  #
  # The asymmetry between them is the point. Stars come from a fetch against
  # the host that may not have happened, so nil means unknown and is rendered
  # as unknown; a zero is a real zero somebody can act on. Dependents are
  # counted in our own tables, so they can never be unknown and zero is always
  # the truth.
  private def render_stats
    div class: "shard-stats-block" do
      div class: "stat-item" do
        tag "i", class: "fa-solid fa-star icon", "aria-hidden": "true"

        if stars = @shard.github_stars
          strong do
            text stars.to_s
          end
          text " stars"
        else
          text "stars "
          span class: "stat-unknown" do
            text "not indexed"
          end
        end
      end

      div class: "stat-item" do
        tag "i", class: "fa-solid fa-diagram-project icon", "aria-hidden": "true"
        strong do
          text @dependent_count.to_s
        end
        text @dependent_count == 1 ? " dependent" : " dependents"
      end

      div class: "stat-item" do
        tag "i", class: "fa-solid fa-scale-balanced icon", "aria-hidden": "true"
        if license = @shard.license
          text "License: "
          strong do
            text license
          end
        else
          text "License: "
          span class: "stat-unknown" do
            text "not declared"
          end
        end
      end
    end
  end

  # ---- what the registry knows, and does not -------------------------------

  # The states that mean "this row is not a healthy index", each said out loud.
  # They stack: an unreachable repository with no tags is both of those things
  # and a reader deserves both sentences.
  private def render_index_notices
    if reason = @shard.identity_error
      notice "warn", "fa-triangle-exclamation" do
        text "This repository could not be identified, so nothing has been "
        text "indexed for it: #{reason}"
      end
    end

    if @shard.unavailable?
      notice "warn", "fa-plug-circle-xmark" do
        text "The last crawl could not reach this repository on its host. "
        text "The entry stays because repositories come back, and because "
        text "other shards still link to it."
      end
    end

    if @versions.empty?
      notice "info", "fa-tag" do
        text "No tagged releases have been indexed. "
        text "`shards` resolves a version from a git tag, and this "
        text "repository has none we could see, so a dependency on it has to "
        text "name a branch or a commit."
      end
    elsif version = @selected_version
      unless version.indexed?
        notice "info", "fa-hourglass-half" do
          text "Nothing has been indexed for #{version.label} yet. "
          text "The tag is recorded, its shard.yml has not been read, so "
          text "the manifest and dependency list below are empty because "
          text "they are unknown rather than because they are absent."
        end
      end

      if version.yanked
        notice "warn", "fa-ban" do
          text "#{version.label} has been yanked. It stays listed so that "
          text "anything already depending on it can still be resolved, but "
          text "it should not be picked for new work."
        end
      end
    end
  end

  private def notice(level : String, icon : String, &)
    div class: "shard-notice shard-notice-#{level}" do
      tag "i", class: "fa-solid #{icon} shard-notice-icon", "aria-hidden": "true"
      para do
        yield
      end
    end
  end

  # ---- installation --------------------------------------------------------

  private def render_installation
    section class: "shard-section" do
      h2 do
        text "Installation"
      end

      div class: "code-block" do
        pre do
          code do
            text "# Add this to your shard.yml\n"
            text "dependencies:\n"
            text "  #{@shard.name}:\n"
            text "#{install_source_line}"
            if line = install_constraint_line
              text "\n#{line}"
            end
          end
        end
      end

      # An untagged repository is not a broken one, and the snippet above is
      # still the correct thing to write. It is just pinned to a moving branch
      # rather than to a release, and saying so is the difference between a
      # reader copying it knowingly and copying it by accident.
      if @versions.empty?
        para class: "text-muted" do
          text "No release to pin to, so this tracks the default branch and "
          text "will change under you."
        end
      elsif (version = @selected_version) && !version.release?
        para class: "text-muted" do
          text "#{version.version} is a branch, not a release, so this "
          text "tracks it rather than pinning a version."
        end
      end

      para do
        text "Then run:"
      end

      div class: "code-block" do
        pre do
          code do
            text "shards install"
          end
        end
      end
    end
  end

  # The shard.yml stanza for depending on this shard, in the spelling its own
  # host uses. A host we have no shorthand for gets the git source, which is
  # what "all git hosts" means for somebody copying this block.
  private def install_source_line : String
    path = @shard.repo_path

    case @shard.host
    when "github.com"    then "    github: #{path}"
    when "gitlab.com"    then "    gitlab: #{path}"
    when "bitbucket.org" then "    bitbucket: #{path}"
    when "codeberg.org"  then "    codeberg: #{path}"
    else                      "    git: #{@shard.repository_url}"
    end
  end

  # What the dependency is pinned to. A release gets a version constraint; a
  # tracked branch gets the branch, because `version: ~> master` is not a
  # thing `shards` can resolve.
  private def install_constraint_line : String?
    version = @selected_version
    return nil unless version

    if version.release?
      "    version: ~> #{version.version}"
    else
      "    branch: #{version.version}"
    end
  end

  # ---- the manifest --------------------------------------------------------

  private def render_manifest_section
    section class: "shard-section" do
      h2 do
        text "shard.yml"
      end

      manifest = @manifest

      if manifest.nil?
        render_manifest_absent
      elsif manifest.describes_nothing?
        # A real manifest that declares only a name and a version. Extremely
        # common here, and worth stating: the reader learns the shard is a
        # single-file library with no build targets and no dependencies, which
        # is information, not a gap.
        para class: "text-muted" do
          text "This shard.yml declares only a name and a version: no Crystal "
          text "constraint, no dependencies, no targets and no executables. "
          text "It is a plain library with nothing to build."
        end
      else
        render_manifest_facts(manifest)
      end
    end
  end

  private def render_manifest_absent
    para class: "text-muted" do
      if version = @selected_version
        text "No shard.yml has been indexed for #{version.label}. "
      else
        text "No shard.yml has been indexed for this repository. "
      end

      text "You can read it on the "
      a href: @shard.repository_url, target: "_blank", rel: "noopener" do
        text "repository"
      end
      text "."
    end
  end

  private def render_manifest_facts(manifest : StoredManifest)
    tag "dl", class: "manifest-facts" do
      # The Crystal constraint on the version row is written from this same
      # parse, so either would do; the manifest is preferred because it is the
      # file the reader is being shown.
      crystal = manifest.crystal || @selected_version.try(&.crystal_version)
      manifest_fact "Crystal" do
        if crystal
          code do
            text crystal
          end
        else
          span class: "text-muted" do
            text "no constraint declared"
          end
        end
      end

      if license = manifest.license
        manifest_fact "License" do
          text license
        end
      end

      authors = manifest.authors
      if authors.any?
        manifest_fact(authors.size == 1 ? "Author" : "Authors") do
          text authors.join(", ")
        end
      end

      targets = manifest.targets
      if targets.any?
        # targets and executables are the only signal for whether a shard is
        # a library or something you run, so they are shown rather than
        # summarised into a badge that would have to guess.
        manifest_fact(targets.size == 1 ? "Target" : "Targets") do
          ul class: "manifest-list" do
            targets.each do |target|
              li do
                code do
                  text target.name
                end
                if main = target.main
                  span class: "text-muted" do
                    text " from #{main}"
                  end
                end
              end
            end
          end
        end
      end

      executables = manifest.executables
      if executables.any?
        manifest_fact(executables.size == 1 ? "Executable" : "Executables") do
          ul class: "manifest-list" do
            executables.each do |executable|
              li do
                code do
                  text executable
                end
              end
            end
          end
        end
      end
    end
  end

  private def manifest_fact(label : String, &)
    tag "dt" do
      text label
    end
    tag "dd" do
      yield
    end
  end

  # ---- dependencies --------------------------------------------------------

  # Always rendered when a version is selected. "This version declares no
  # dependencies" is a fact a reader came for; an omitted section is
  # indistinguishable from a section that failed to load.
  private def render_dependencies_section
    return if @versions.empty?

    runtime_deps = @dependencies.select { |dependency| dependency.scope == "runtime" }
    dev_deps = @dependencies.select { |dependency| dependency.scope == "development" }

    section class: "shard-section" do
      h2 do
        text "Dependencies"
      end

      if runtime_deps.any?
        h3 class: "shard-subhead" do
          text "Runtime Dependencies"
        end

        ul class: "dependency-list" do
          runtime_deps.each { |dependency| render_dependency_item(dependency) }
        end
      end

      if dev_deps.any?
        h3 class: "shard-subhead" do
          text "Development Dependencies"
        end

        ul class: "dependency-list" do
          dev_deps.each { |dependency| render_dependency_item(dependency) }
        end
      end

      if runtime_deps.empty? && dev_deps.empty?
        para class: "text-muted" do
          if @selected_version.try(&.indexed?)
            text "This version declares no dependencies."
          else
            text "Unknown: the shard.yml for this version has not been read yet."
          end
        end
      end
    end
  end

  # A dependency is recorded as a shard.yml name, and a name no longer
  # identifies a shard. UpdateDependenciesWorker resolves each dependency to a
  # specific repository when the shard.yml said which host it comes from
  # ("github: owner/repo"), and that resolved row is the only thing worth
  # linking to. When there is no resolved row, the name is rendered as text:
  # the alternative is linking to whichever "router" came back first, which is
  # how somebody installs the wrong dependency.
  private def render_dependency_item(dependency : Dependency)
    li do
      if link = dependency_link(dependency)
        a href: link, class: "dependency-link" do
          strong do
            text dependency.name
          end
        end
      else
        strong do
          text dependency.name
        end
      end

      span class: "dependency-requirement" do
        text dependency.version_requirement
      end

      # The source is the half of a dependency the row does not carry, and it
      # is the half that says whether the requirement tracks a release or
      # somebody's branch.
      if source = @manifest.try(&.source_for(dependency.name))
        span class: "dependency-source" do
          text source
        end
      elsif dependency_link(dependency).nil?
        span class: "dependency-source text-muted" do
          text "not in the registry"
        end
      end

      if dependency.scope == "development"
        span class: "badge badge-dev" do
          text "dev"
        end
      end
    end
  end

  private def dependency_link(dependency : Dependency) : String?
    dependency.dependent_shard.try(&.url_path)
  end

  # ---- readme --------------------------------------------------------------

  private def render_readme_section
    section class: "shard-section" do
      h2 do
        text "README"
      end

      div class: "readme-content" do
        if readme = @shard.readme_content
          # The README is indexed once per repository, at its latest ref, not
          # once per tag. Saying so on an older version stops a reader
          # attributing this text to a release it may not describe.
          if showing_older_version?
            para class: "text-muted" do
              text "This README is the one indexed from the repository at its "
              text "latest ref, not from the tag for this version."
            end
          end

          # The block scrolls, so it must be focusable or a keyboard user
          # cannot reach its content (WCAG 2.1.1).
          tag "pre", class: "readme-raw", tabindex: "0", role: "region",
            "aria-label": "README for #{@shard.name}" do
            text readme
          end
        else
          para do
            text "No README has been indexed for this shard yet. You can read it on the "
            a href: @shard.repository_url, target: "_blank", rel: "noopener" do
              text "repository"
            end
            text "."
          end
        end
      end
    end
  end

  # ---- sidebar -------------------------------------------------------------

  private def render_links
    section class: "sidebar-section" do
      h3 do
        text "Links"
      end

      ul class: "link-list" do
        li do
          a href: @shard.repository_url, target: "_blank", rel: "noopener" do
            text "Repository"
          end
        end

        if homepage = @shard.homepage_url
          li do
            a href: homepage, target: "_blank", rel: "noopener" do
              text "Homepage"
            end
          end
        end

        if docs_url = @shard.documentation_url
          li do
            a href: docs_url, target: "_blank", rel: "noopener" do
              text "Documentation"
            end
          end
        end
      end
    end
  end

  # What is true of the version on screen specifically, as opposed to the
  # repository. Rendered even when the version has nothing indexed, because
  # "recorded on this date, not yet read" is the state a reader needs.
  private def render_selected_version_section
    version = @selected_version
    return unless version

    section class: "sidebar-section" do
      h3 do
        text version.release? ? "This release" : "This branch"
      end

      tag "dl", class: "meta-facts" do
        manifest_fact version.release? ? "Version" : "Branch" do
          code do
            text version.version
          end
        end

        manifest_fact version.release? ? "Tagged" : "Seen" do
          text format_date(version.released_at)
        end

        if sha = version.commit_sha
          manifest_fact "Commit" do
            code do
              text sha[0, {sha.size, 12}.min]
            end
          end
        end

        if crystal_version = version.crystal_version
          manifest_fact "Crystal" do
            code do
              text crystal_version
            end
          end
        end

        manifest_fact "Indexed" do
          if version.indexed?
            text "yes"
          else
            span class: "text-muted" do
              text "not yet"
            end
          end
        end
      end
    end
  end

  # The other half of popularity, and the half a bare number cannot show. A
  # count with nothing behind it is the dead end this page exists to stop
  # being, so the dependents are named and linked.
  private def render_dependents_section
    section class: "sidebar-section" do
      h3 do
        text "Dependents"
      end

      if @dependents.empty?
        para class: "text-muted" do
          text "No indexed shard depends on this one yet."
        end
      else
        ul class: "link-list" do
          @dependents.each do |dependent|
            li do
              a href: dependent.url_path do
                text dependent.name
              end
            end
          end
        end

        remaining = @dependent_count - @dependents.size
        if remaining > 0
          para class: "version-list-footer" do
            text "and #{remaining} more"
          end
        end
      end
    end
  end

  private def render_repository_section
    section class: "sidebar-section" do
      h3 do
        text "Repository"
      end

      # The identity, spelled out. With two shards able to share a name,
      # this is what tells a reader which one they are looking at.
      para do
        if slug = @shard.canonical_slug
          text slug
        else
          text @shard.provider.capitalize
        end
      end

      # A row with no identity says why, here, rather than leaving
      # somebody to wonder why the shard never indexed.
      if reason = @shard.identity_error
        para class: "text-muted" do
          text "Not indexed: #{reason}"
        end
      end

      if @shard.unavailable?
        para class: "text-muted" do
          text "This repository could not be reached on its host the last time we looked."
        end
      end
    end
  end

  private def render_registry_section
    section class: "sidebar-section" do
      h3 do
        text "Metadata"
      end

      tag "dl", class: "meta-facts" do
        manifest_fact "Created" do
          text format_date(@shard.created_at)
        end

        manifest_fact "Updated" do
          text format_date(@shard.updated_at)
        end

        manifest_fact "Synced" do
          if synced = @shard.last_synced_at
            text format_date(synced)
          else
            span class: "text-muted" do
              text "never"
            end
          end
        end

        manifest_fact "Versions" do
          if @versions.empty?
            span class: "text-muted" do
              text "none tagged"
            end
          else
            text @versions.size.to_s
          end
        end
      end
    end
  end

  # ---- helpers -------------------------------------------------------------

  private def showing_older_version? : Bool
    selected = @selected_version
    newest = @versions.first?
    return false if selected.nil? || newest.nil?

    selected.version != newest.version
  end

  # Timestamps are UTC instants. Rendering them in the database session's
  # zone would shift the displayed day depending on where the server runs,
  # so pin the display to UTC.
  private def format_date(time : Time) : String
    time.to_utc.to_s("%b %-d, %Y")
  end
end
