class Components::DocNavigation < Lucky::BaseComponent
  needs package_name : String
  needs version : String
  needs nav_files : Array(String)
  needs current_file : String

  def render
    nav class: "doc-nav-sidebar" do
      h3 "Navigation"

      render_nav_tree
    end
  end

  private def render_nav_tree
    # Group files by directory
    grouped = group_files_by_directory(nav_files)

    ul class: "nav-tree" do
      grouped.each do |dir, files|
        render_nav_group(dir, files)
      end
    end
  end

  private def render_nav_group(directory : String, files : Array(String))
    if directory.empty?
      # Root level files
      files.each do |file|
        render_nav_item(file)
      end
    else
      # Directory with files
      li class: "nav-group" do
        details open: is_current_directory?(directory) do
          summary directory.split("/").last.titleize

          ul do
            files.each do |file|
              render_nav_item(file)
            end
          end
        end
      end
    end
  end

  private def render_nav_item(file : String)
    li class: nav_item_class(file) do
      a display_name(file), href: doc_file_path(file)
    end
  end

  private def nav_item_class(file : String) : String
    file == current_file ? "nav-item active" : "nav-item"
  end

  private def doc_file_path(file : String) : String
    "/docs/#{package_name}/#{version}/#{file}"
  end

  private def display_name(file : String) : String
    # Remove directory prefix and .html extension
    name = file.split("/").last.gsub(".html", "")
    name.gsub("-", " ").gsub("_", " ").titleize
  end

  private def group_files_by_directory(files : Array(String)) : Hash(String, Array(String))
    grouped = Hash(String, Array(String)).new

    files.each do |file|
      # Skip non-HTML files
      next unless file.ends_with?(".html")

      # Determine directory
      parts = file.split("/")
      if parts.size == 1
        # Root level file
        grouped[""] ||= [] of String
        grouped[""] << file
      else
        # File in subdirectory
        dir = parts[0...-1].join("/")
        grouped[dir] ||= [] of String
        grouped[dir] << file
      end
    end

    grouped
  end

  private def is_current_directory?(directory : String) : Bool
    current_file.starts_with?(directory)
  end
end
