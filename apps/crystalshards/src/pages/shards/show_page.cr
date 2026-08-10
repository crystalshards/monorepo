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
              strong do
                text "⭐ #{stars}"
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
                    text "    github: #{extract_github_path(@shard.repository_url)}\n"
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
              text "Provider"
            end

            para do
              text @shard.provider.capitalize
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

  private def render_dependency_item(dep : Dependency)
    li do
      a href: Shards::Show.with(dep.name).path, class: "dependency-link" do
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

  private def extract_github_path(url : String) : String
    url.gsub(%r{https?://github\.com/}, "").gsub(/\.git$/, "")
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
