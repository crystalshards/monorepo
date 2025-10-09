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
          h1 class: "shard-title" do
            text @shard.name
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

          if @dependencies.any?
            section class: "shard-section" do
              h2 do
                text "Dependencies"
              end

              ul class: "dependency-list" do
                @dependencies.each do |dep|
                  li do
                    strong do
                      text dep.name
                    end
                    text " #{dep.version_requirement}"
                    if dep.scope == "development"
                      span class: "badge badge-dev" do
                        text "dev"
                      end
                    end
                  end
                end
              end
            end
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
        end
      end
    end
  end

  private def extract_github_path(url : String) : String
    url.gsub(%r{https?://github\.com/}, "").gsub(/\.git$/, "")
  end

  private def format_date(time : Time) : String
    time.to_s("%b %-d, %Y")
  end

  private def version_li_class(version : ShardVersion) : String
    version.yanked ? "version-yanked" : ""
  end
end
