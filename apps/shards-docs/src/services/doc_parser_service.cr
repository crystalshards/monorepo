require "json"

module CrystalDocs
  # Service for parsing and enhancing documentation content
  class DocParserService
    
    # Parse HTML documentation and extract metadata
    def self.parse_documentation(content : String, package_name : String, version : String)
      metadata = {
        package_name: package_name,
        version: version,
        title: extract_title(content),
        description: extract_description(content),
        modules: extract_modules(content),
        classes: extract_classes(content),
        methods: extract_methods(content),
        links: extract_links(content),
        toc: generate_table_of_contents(content)
      }
      
      metadata
    end
    
    # Extract page title from HTML
    def self.extract_title(content : String) : String
      if match = content.match(/<title[^>]*>([^<]+)<\/title>/i)
        match[1].strip
      elsif match = content.match(/<h1[^>]*>([^<]+)<\/h1>/i)
        match[1].strip
      else
        "Documentation"
      end
    end
    
    # Extract description from meta tag or first paragraph
    def self.extract_description(content : String) : String
      # Try meta description first
      if match = content.match(/<meta\s+name=['"]description['"][^>]*content=['"]([^'"]+)['"][^>]*>/i)
        return match[1].strip
      end
      
      # Try first paragraph
      if match = content.match(/<p[^>]*>([^<]+)<\/p>/i)
        return match[1].strip.gsub(/\s+/, " ").truncate(200)
      end
      
      "Crystal package documentation"
    end
    
    # Extract module definitions from documentation
    def self.extract_modules(content : String) : Array(Hash(String, String))
      modules = [] of Hash(String, String)
      
      # Look for Crystal module patterns
      content.scan(/module\s+([A-Z][a-zA-Z0-9_:]+)/m) do |match|
        module_name = match[1]
        modules << {
          "name" => module_name,
          "type" => "module",
          "link" => "#module-#{module_name.downcase.gsub("::", "-")}"
        }
      end
      
      # Look for HTML sections that might represent modules
      content.scan(/<h[2-4][^>]*id=['"]([^'"]*module[^'"]*|[^'"]*[A-Z][a-zA-Z0-9_]+)['"][^>]*>([^<]+)<\/h[2-4]>/i) do |match|
        id = match[1]
        title = match[2].strip
        
        if title.includes?("module") || title.match(/^[A-Z][a-zA-Z0-9_:]+$/)
          modules << {
            "name" => title,
            "type" => "module",
            "link" => "##{id}"
          }
        end
      end
      
      modules.uniq_by { |m| m["name"] }
    end
    
    # Extract class definitions from documentation
    def self.extract_classes(content : String) : Array(Hash(String, String))
      classes = [] of Hash(String, String)
      
      # Look for Crystal class patterns
      content.scan(/class\s+([A-Z][a-zA-Z0-9_:]+)/m) do |match|
        class_name = match[1]
        classes << {
          "name" => class_name,
          "type" => "class",
          "link" => "#class-#{class_name.downcase.gsub("::", "-")}"
        }
      end
      
      # Look for struct patterns
      content.scan(/struct\s+([A-Z][a-zA-Z0-9_:]+)/m) do |match|
        struct_name = match[1]
        classes << {
          "name" => struct_name,
          "type" => "struct",
          "link" => "#struct-#{struct_name.downcase.gsub("::", "-")}"
        }
      end
      
      # Look for HTML sections that might represent classes
      content.scan(/<h[2-4][^>]*id=['"]([^'"]*class[^'"]*|[^'"]*[A-Z][a-zA-Z0-9_]+)['"][^>]*>([^<]+)<\/h[2-4]>/i) do |match|
        id = match[1]
        title = match[2].strip
        
        if title.includes?("class") || title.match(/^[A-Z][a-zA-Z0-9_:]+$/)
          classes << {
            "name" => title,
            "type" => "class",
            "link" => "##{id}"
          }
        end
      end
      
      classes.uniq_by { |c| c["name"] }
    end
    
    # Extract method definitions from documentation
    def self.extract_methods(content : String) : Array(Hash(String, String))
      methods = [] of Hash(String, String)
      
      # Look for Crystal method patterns
      content.scan(/def\s+([a-zA-Z_][a-zA-Z0-9_!?]*)/m) do |match|
        method_name = match[1]
        methods << {
          "name" => method_name,
          "type" => "method",
          "link" => "#method-#{method_name.downcase.gsub(/[!?]/, "")}"
        }
      end
      
      # Look for getter/setter patterns
      content.scan(/getter\s+([a-zA-Z_][a-zA-Z0-9_]*)/m) do |match|
        getter_name = match[1]
        methods << {
          "name" => getter_name,
          "type" => "getter",
          "link" => "#getter-#{getter_name.downcase}"
        }
      end
      
      content.scan(/setter\s+([a-zA-Z_][a-zA-Z0-9_]*)/m) do |match|
        setter_name = match[1]
        methods << {
          "name" => "#{setter_name}=",
          "type" => "setter",
          "link" => "#setter-#{setter_name.downcase}"
        }
      end
      
      # Look for HTML method signatures
      content.scan(/<h[3-6][^>]*id=['"]([^'"]*method[^'"]*|[^'"]*[a-z_][a-zA-Z0-9_!?]*)['"][^>]*>([^<]+)<\/h[3-6]>/i) do |match|
        id = match[1]
        title = match[2].strip
        
        if title.includes?("method") || title.match(/^[a-z_][a-zA-Z0-9_!?]*(\(|$)/)
          method_name = title.gsub(/\(.*\)/, "").strip
          methods << {
            "name" => method_name,
            "type" => "method",
            "link" => "##{id}"
          }
        end
      end
      
      methods.uniq_by { |m| m["name"] }
    end
    
    # Extract all links from documentation
    def self.extract_links(content : String) : Array(Hash(String, String))
      links = [] of Hash(String, String)
      
      content.scan(/<a\s+[^>]*href=['"]([^'"]+)['"][^>]*>([^<]+)<\/a>/i) do |match|
        href = match[1]
        text = match[2].strip
        
        # Categorize links
        link_type = case
        when href.starts_with?("http")
          "external"
        when href.starts_with?("#")
          "anchor"
        when href.ends_with?(".html")
          "page"
        else
          "internal"
        end
        
        links << {
          "url" => href,
          "text" => text,
          "type" => link_type
        }
      end
      
      links
    end
    
    # Generate table of contents from headings
    def self.generate_table_of_contents(content : String) : Array(Hash(String, String | Int32))
      toc = [] of Hash(String, String | Int32)
      
      content.scan(/<h([1-6])[^>]*(?:id=['"]([^'"]*)['"])?[^>]*>([^<]+)<\/h[1-6]>/i) do |match|
        level = match[1].to_i
        id = match[2]? || generate_id(match[3])
        title = match[3].strip
        
        toc << {
          "level" => level,
          "title" => title,
          "id" => id,
          "link" => "##{id}"
        }
      end
      
      toc
    end
    
    # Enhance documentation with cross-references and search metadata
    def self.enhance_documentation(content : String, package_name : String, version : String) : String
      enhanced_content = content
      
      # Add navigation breadcrumbs
      breadcrumbs = generate_breadcrumbs(package_name, version)
      enhanced_content = add_breadcrumbs(enhanced_content, breadcrumbs)
      
      # Add inter-package links
      enhanced_content = add_cross_references(enhanced_content, package_name)
      
      # Add search metadata
      enhanced_content = add_search_metadata(enhanced_content, package_name, version)
      
      # Add responsive design improvements
      enhanced_content = add_responsive_styles(enhanced_content)
      
      enhanced_content
    end
    
    # Generate breadcrumb navigation
    def self.generate_breadcrumbs(package_name : String, version : String) : String
      <<-HTML
      <nav class="breadcrumbs" style="padding: 10px 0; border-bottom: 1px solid #eee; margin-bottom: 20px;">
        <a href="/" style="text-decoration: none; color: #007bff;">CrystalDocs</a>
        <span style="margin: 0 5px; color: #666;">›</span>
        <a href="/search?q=#{package_name}" style="text-decoration: none; color: #007bff;">#{package_name}</a>
        <span style="margin: 0 5px; color: #666;">›</span>
        <span style="color: #666;">#{version}</span>
      </nav>
      HTML
    end
    
    # Add breadcrumbs to documentation
    def self.add_breadcrumbs(content : String, breadcrumbs : String) : String
      if match = content.match(/(<body[^>]*>)/i)
        content.sub(match[0], "#{match[0]}\n#{breadcrumbs}")
      else
        content
      end
    end
    
    # Add cross-references to other packages
    def self.add_cross_references(content : String, package_name : String) : String
      # This would query the database for related packages and add links
      # For now, just add a simple related packages section
      
      related_section = <<-HTML
      <div class="related-packages" style="margin-top: 40px; padding: 20px; background: #f8f9fa; border-radius: 4px;">
        <h3>Explore More Packages</h3>
        <p><a href="/search">Browse all Crystal packages</a> | <a href="/api/v1/docs">Latest documentation builds</a></p>
      </div>
      HTML
      
      if match = content.match(/(<\/body>)/i)
        content.sub(match[0], "#{related_section}\n#{match[0]}")
      else
        content + related_section
      end
    end
    
    # Add search metadata to HTML head
    def self.add_search_metadata(content : String, package_name : String, version : String) : String
      metadata = <<-HTML
      <meta name="package" content="#{package_name}">
      <meta name="version" content="#{version}">
      <meta name="generator" content="CrystalDocs">
      <link rel="canonical" href="https://crystaldocs.org/docs/#{package_name}/#{version}">
      HTML
      
      if match = content.match(/(<\/head>)/i)
        content.sub(match[0], "#{metadata}\n#{match[0]}")
      else
        content
      end
    end
    
    # Add responsive design improvements
    def self.add_responsive_styles(content : String) : String
      responsive_css = <<-CSS
      <style>
        @media (max-width: 768px) {
          body { margin: 10px; font-size: 14px; }
          .sidebar { width: 100%; height: auto; position: static; padding: 10px; }
          .content { margin-left: 0; }
          pre { overflow-x: auto; }
          table { font-size: 12px; }
        }
        .search-highlight { background-color: yellow; }
        .copy-button { 
          float: right; 
          background: #007bff; 
          color: white; 
          border: none; 
          padding: 2px 8px; 
          border-radius: 3px; 
          cursor: pointer; 
          font-size: 11px;
        }
        pre { position: relative; }
        .copy-button:hover { background: #0056b3; }
      </style>
      CSS
      
      if match = content.match(/(<\/head>)/i)
        content.sub(match[0], "#{responsive_css}\n#{match[0]}")
      else
        content + responsive_css
      end
    end
    
    # Generate URL-friendly ID from text
    def self.generate_id(text : String) : String
      text.downcase
          .gsub(/[^a-z0-9_\-\s]/, "")
          .gsub(/\s+/, "-")
          .gsub(/-+/, "-")
          .strip("-")
    end
    
    # Extract code examples from documentation
    def self.extract_code_examples(content : String) : Array(Hash(String, String))
      examples = [] of Hash(String, String)
      
      content.scan(/<pre[^>]*><code[^>]*(?:class=['"]([^'"]*)['"])?[^>]*>([^<]+)<\/code><\/pre>/im) do |match|
        language = match[1]? || "crystal"
        code = match[2].strip
        
        examples << {
          "language" => language,
          "code" => code,
          "snippet" => code.lines.first(3).join("\n") + (code.lines.size > 3 ? "..." : "")
        }
      end
      
      examples
    end
    
    # Index documentation content for search
    def self.create_search_index(content : String, package_name : String, version : String)
      # Extract searchable text content
      text_content = content
        .gsub(/<[^>]+>/, " ")
        .gsub(/\s+/, " ")
        .strip
      
      # Extract keywords
      keywords = extract_keywords(text_content, package_name)
      
      {
        package_name: package_name,
        version: version,
        content: text_content,
        keywords: keywords,
        indexed_at: Time.utc.to_s
      }
    end
    
    private def self.extract_keywords(text : String, package_name : String) : Array(String)
      keywords = [package_name]
      
      # Extract common programming terms and Crystal-specific terms
      crystal_terms = %w[class module struct def getter setter property enum alias annotation macro require include extend]
      
      words = text.downcase.scan(/\b[a-z_][a-z0-9_]*\b/).map(&.[0])
      
      # Add Crystal keywords found in text
      crystal_terms.each do |term|
        keywords << term if words.includes?(term)
      end
      
      # Add common method names and identifiers
      words.select { |w| w.size > 2 }.uniq.first(20).each do |word|
        keywords << word
      end
      
      keywords.uniq
    end
  end
end