class Shards::ShowPage < MainLayout
  needs shard : Shard
  needs versions : Array(ShardVersion)
  needs dependencies : Array(Dependency)
  needs latest_version : ShardVersion?

  def page_title
    @shard.name
  end

  def content
    section class: "section" do
      div class: "shard-header" do
        div class: "shard-title-block" do
          div style: "display: flex; align-items: center; gap: 1rem; flex-wrap: wrap;" do
            h1 class: "shard-title", style: "margin: 0;" do
              text @shard.name
            end

            if latest = @latest_version
              span class: "badge", style: "background-color: var(--link-color); color: var(--white); padding: 0.4rem 0.8rem; font-size: 1rem;" do
                text "v#{latest.version}"
              end
            end
          end

          if description = @shard.description
            para class: "shard-description-large" do
              text description
            end
          end
        end

        div class: "shard-stats-block" do
          if stars = @shard.github_stars
            div class: "stat-item" do
              tag "i", class: "fa-solid fa-star icon", "aria-hidden": "true"
              strong do
                text stars.to_s
              end
              text " stars"
            end
          end

          div class: "stat-item" do
            strong do
              text @shard.total_downloads.to_s
            end
            text " downloads"
          end

          if license = @shard.license
            div class: "stat-item" do
              strong do
                text "License:"
              end
              text " #{license}"
            end
          end
        end
      end

      div class: "shard-content" do
        div class: "shard-main" do
          section class: "shard-section" do
            h2 do
              text "Installation"
            end

            if latest = @latest_version
              div class: "code-block" do
                pre do
                  code do
                    text "# Add this to your shard.yml\n"
                    text "dependencies:\n"
                    text "  #{@shard.name}:\n"
                    text "#{install_source_line}\n"
                    text "    version: ~> #{latest.version}"
                  end
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

          render_readme_section

          if @dependencies.any?
            render_dependencies_section
          end

          if docs_url = @shard.documentation_url
            section class: "shard-section" do
              h2 do
                text "Documentation"
              end

              para do
                a href: docs_url, target: "_blank", class: "button button-primary" do
                  text "View Documentation"
                end
              end
            end
          end
        end

        div class: "shard-sidebar" do
          section class: "sidebar-section" do
            h3 do
              text "Links"
            end

            ul class: "link-list" do
              li do
                a href: @shard.repository_url, target: "_blank" do
                  text "Repository"
                end
              end

              if homepage = @shard.homepage_url
                li do
                  a href: homepage, target: "_blank" do
                    text "Homepage"
                  end
                end
              end

              if docs_url = @shard.documentation_url
                li do
                  a href: docs_url, target: "_blank" do
                    text "Documentation"
                  end
                end
              end
            end
          end

          if @versions.any?
            section class: "sidebar-section" do
              h3 do
                text "Versions"
              end

              ul class: "version-list" do
                @versions.first(10).each do |version|
                  li class: version_li_class(version) do
                    span class: "version-number" do
                      text version.version
                    end
                    span class: "version-date" do
                      text format_date(version.released_at)
                    end
                  end
                end
              end

              if @versions.size > 10
                para class: "version-list-footer" do
                  text "and #{@versions.size - 10} more..."
                end
              end
            end
          end

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

          section class: "sidebar-section" do
            h3 do
              text "Metadata"
            end

            div style: "display: flex; flex-direction: column; gap: 0.5rem;" do
              div do
                strong do
                  text "Created: "
                end
                text format_date(@shard.created_at)
              end

              div do
                strong do
                  text "Updated: "
                end
                text format_date(@shard.updated_at)
              end

              if crystal_version = @latest_version.try(&.crystal_version)
                div do
                  strong do
                    text "Crystal: "
                  end
                  text crystal_version
                end
              end
            end
          end
        end
      end
    end
  end

  private def render_readme_section
    section class: "shard-section" do
      h2 do
        text "README"
      end

      div class: "readme-content" do
        if readme = @shard.readme_content
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

  private def render_dependencies_section
    runtime_deps = @dependencies.select { |d| d.scope == "runtime" }
    dev_deps = @dependencies.select { |d| d.scope == "development" }

    section class: "shard-section" do
      h2 do
        text "Dependencies"
      end

      if runtime_deps.any?
        h3 style: "font-size: 1.1rem; margin-bottom: 0.5rem;" do
          text "Runtime Dependencies"
        end

        ul class: "dependency-list" do
          runtime_deps.each do |dep|
            render_dependency_item(dep)
          end
        end
      end

      if dev_deps.any?
        h3 style: "font-size: 1.1rem; margin: 1.5rem 0 0.5rem 0;" do
          text "Development Dependencies"
        end

        ul class: "dependency-list" do
          dev_deps.each do |dep|
            render_dependency_item(dep)
          end
        end
      end

      if runtime_deps.empty? && dev_deps.empty?
        para class: "text-muted" do
          text "No dependencies"
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
  private def render_dependency_item(dep : Dependency)
    li do
      if link = dependency_link(dep)
        a href: link, class: "dependency-link" do
          strong do
            text dep.name
          end
        end
      else
        strong do
          text dep.name
        end
      end

      text " #{dep.version_requirement}"
      if dep.scope == "development"
        span class: "badge badge-dev" do
          text "dev"
        end
      end
    end
  end

  private def dependency_link(dep : Dependency) : String?
    dep.dependent_shard.try(&.url_path)
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

  # Timestamps are UTC instants. Rendering them in the database session's
  # zone would shift the displayed day depending on where the server runs,
  # so pin the display to UTC.
  private def format_date(time : Time) : String
    time.to_utc.to_s("%b %-d, %Y")
  end

  private def version_li_class(version : ShardVersion) : String
    version.yanked ? "version-yanked" : ""
  end
end
