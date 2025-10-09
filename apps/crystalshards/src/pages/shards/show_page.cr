class Shards::ShowPage < MainLayout
  needs shard : Shard
  needs versions : Array(ShardVersion)
  needs dependencies : Array(Dependency)
  needs latest_version : ShardVersion?
  needs dependents : Array(Shard)

  def page_title
    @shard.name
  end

  def content
    render_copy_script

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

          if latest = @latest_version
            div class: "shard-version-badge" do
              text "v#{latest.version}"
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

          if forks = @shard.github_forks
            div class: "stat-item" do
              strong do
                text "🍴 #{forks}"
              end
              text " forks"
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

          div class: "stat-item stat-item-muted" do
            text "Updated #{format_relative_time(@shard.updated_at)}"
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
              div class: "installation-block" do
                div class: "code-block-header" do
                  span do
                    text "shard.yml"
                  end
                  button class: "copy-button", onclick: "copyToClipboard('install-code')", type: "button" do
                    text "📋 Copy"
                  end
                end

                div class: "code-block", id: "install-code-wrapper" do
                  pre do
                    code id: "install-code" do
                      text "# Add this to your shard.yml\n"
                      text "dependencies:\n"
                      text "  #{@shard.name}:\n"
                      text "    github: #{extract_github_path(@shard.repository_url)}\n"
                      text "    version: ~> #{latest.version}"
                    end
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
            section class: "shard-section" do
              h2 do
                text "Dependencies"
              end

              ul class: "dependency-list" do
                @dependencies.each do |dep|
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
              end
            end
          end

          if @dependents.any?
            section class: "shard-section" do
              h2 do
                text "Dependents"
              end

              para class: "dependents-count" do
                text "#{@dependents.size} shard#{@dependents.size == 1 ? "" : "s"} depend on #{@shard.name}"
              end

              ul class: "dependency-list" do
                @dependents.first(10).each do |dependent|
                  li do
                    a href: Shards::Show.with(dependent.name).path, class: "dependency-link" do
                      strong do
                        text dependent.name
                      end
                    end
                    if desc = dependent.description
                      span class: "dependency-description" do
                        text " - #{desc}"
                      end
                    end
                  end
                end
              end

              if @dependents.size > 10
                para class: "dependents-footer" do
                  text "and #{@dependents.size - 10} more..."
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
              text "Metadata"
            end

            ul class: "metadata-list" do
              li do
                strong do
                  text "Created:"
                end
                text " #{format_date(@shard.created_at)}"
              end

              li do
                strong do
                  text "Updated:"
                end
                text " #{format_date(@shard.updated_at)}"
              end

              li do
                strong do
                  text "Provider:"
                end
                text " #{@shard.provider.capitalize}"
              end

              if last_synced = @shard.last_synced_at
                li do
                  strong do
                    text "Last synced:"
                  end
                  text " #{format_relative_time(last_synced)}"
                end
              end
            end
          end

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
                text "Versions (#{@versions.size})"
              end

              ul class: "version-list" do
                @versions.first(10).each do |version|
                  li class: version_li_class(version) do
                    div class: "version-info" do
                      span class: "version-number" do
                        text version.version
                      end
                      span class: "version-date" do
                        text format_date(version.released_at)
                      end
                    end
                    render_version_downloads(version)
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
        end
      end
    end
  end

  private def render_readme_section
    if readme = @shard.readme_content
      section class: "shard-section" do
        h2 do
          text "README"
        end

        div class: "readme-content" do
          pre do
            text readme
          end
        end
      end
    end
  end

  private def render_version_downloads(version : ShardVersion)
    downloads_count = version.downloads.size
    if downloads_count > 0
      div class: "version-downloads" do
        text "#{downloads_count} download#{downloads_count == 1 ? "" : "s"}"
      end
    end
  end

  private def extract_github_path(url : String) : String
    url.gsub(%r{https?://github\.com/}, "").gsub(/\.git$/, "")
  end

  private def format_date(time : Time) : String
    time.to_s("%b %-d, %Y")
  end

  private def format_relative_time(time : Time) : String
    diff = Time.utc - time
    case
    when diff < 1.minute
      "moments ago"
    when diff < 1.hour
      "#{diff.total_minutes.to_i} minutes ago"
    when diff < 1.day
      "#{diff.total_hours.to_i} hours ago"
    when diff < 7.days
      "#{diff.total_days.to_i} days ago"
    when diff < 30.days
      "#{(diff.total_days / 7).to_i} weeks ago"
    when diff < 365.days
      "#{(diff.total_days / 30).to_i} months ago"
    else
      "#{(diff.total_days / 365).to_i} years ago"
    end
  end

  private def version_li_class(version : ShardVersion) : String
    version.yanked ? "version-yanked" : ""
  end

  private def render_copy_script
    script do
      raw <<-JS
        function copyToClipboard(elementId) {
          const element = document.getElementById(elementId);
          if (!element) return;

          const text = element.textContent;
          navigator.clipboard.writeText(text).then(() => {
            const button = event.target;
            const originalText = button.textContent;
            button.textContent = '✓ Copied!';
            setTimeout(() => {
              button.textContent = originalText;
            }, 2000);
          }).catch(err => {
            console.error('Failed to copy:', err);
          });
        }
      JS
    end
  end
end
