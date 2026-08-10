class Db::Seed::SampleData < LuckyTask::Task
  summary "Add sample database records helpful for development"

  @storage = CrystalDocs::DocsStorageService.new
  @storage_available = false

  def call
    @storage_available = @storage.ensure_bucket

    unless @storage_available
      puts "WARNING: object storage is unreachable. Seeding metadata only, and"
      puts "         versions will be marked failed rather than claiming docs"
      puts "         that are not there. Start MinIO and re-run to fix."
    end

    seed_documentation
    puts "Done adding sample data"
  end

  private def seed_documentation
    puts "Seeding documentation entries..."

    create_doc_with_versions(
      package_name: "lucky",
      description: "A full-featured Crystal web framework that catches bugs for you, runs incredibly fast, and helps you write code that lasts.",
      repository_url: "https://github.com/luckyframework/lucky",
      versions: [
        {version: "0.28.0", released_at: 2.months.ago, file_count: 150, total_size: 2_500_000_i64},
        {version: "0.29.0", released_at: 1.month.ago, file_count: 158, total_size: 2_600_000_i64},
        {version: "1.0.0", released_at: 1.week.ago, file_count: 165, total_size: 2_800_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "kemal",
      description: "Lightning Fast, Super Simple web framework for Crystal.",
      repository_url: "https://github.com/kemalcr/kemal",
      versions: [
        {version: "1.2.0", released_at: 6.months.ago, file_count: 80, total_size: 1_200_000_i64},
        {version: "1.3.0", released_at: 3.months.ago, file_count: 85, total_size: 1_300_000_i64},
        {version: "1.4.0", released_at: 2.weeks.ago, file_count: 90, total_size: 1_400_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "amber",
      description: "A Crystal web framework that makes building applications fast, simple, and enjoyable.",
      repository_url: "https://github.com/amberframework/amber",
      versions: [
        {version: "1.2.0", released_at: 4.months.ago, file_count: 120, total_size: 1_800_000_i64},
        {version: "1.3.0", released_at: 1.month.ago, file_count: 125, total_size: 1_900_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "granite",
      description: "ORM for Crystal. Inspired by ActiveRecord and Ecto.",
      repository_url: "https://github.com/amberframework/granite",
      versions: [
        {version: "0.23.0", released_at: 5.months.ago, file_count: 60, total_size: 900_000_i64},
        {version: "0.24.0", released_at: 2.months.ago, file_count: 62, total_size: 920_000_i64},
        {version: "0.25.0", released_at: 2.weeks.ago, file_count: 65, total_size: 950_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "jennifer",
      description: "Active Record pattern implementation for Crystal with flexible query chainable builder and migration system.",
      repository_url: "https://github.com/imdrasil/jennifer.cr",
      versions: [
        {version: "0.11.0", released_at: 6.months.ago, file_count: 95, total_size: 1_500_000_i64},
        {version: "0.12.0", released_at: 3.months.ago, file_count: 100, total_size: 1_550_000_i64},
        {version: "0.13.0", released_at: 3.weeks.ago, file_count: 105, total_size: 1_600_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "ameba",
      description: "A static code analysis tool for Crystal.",
      repository_url: "https://github.com/crystal-ameba/ameba",
      versions: [
        {version: "1.4.0", released_at: 4.months.ago, file_count: 40, total_size: 600_000_i64},
        {version: "1.5.0", released_at: 1.month.ago, file_count: 42, total_size: 620_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "spec-kemal",
      description: "Easy testing for Kemal applications.",
      repository_url: "https://github.com/kemalcr/spec-kemal",
      versions: [
        {version: "1.0.0", released_at: 8.months.ago, file_count: 25, total_size: 400_000_i64},
        {version: "1.1.0", released_at: 2.months.ago, file_count: 28, total_size: 430_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "crystal-redis",
      description: "Full featured Redis client for Crystal.",
      repository_url: "https://github.com/stefanwille/crystal-redis",
      versions: [
        {version: "2.8.0", released_at: 5.months.ago, file_count: 70, total_size: 1_100_000_i64},
        {version: "2.9.0", released_at: 1.month.ago, file_count: 72, total_size: 1_150_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "crystal-pg",
      description: "PostgreSQL driver for Crystal.",
      repository_url: "https://github.com/will/crystal-pg",
      versions: [
        {version: "0.24.0", released_at: 7.months.ago, file_count: 55, total_size: 850_000_i64},
        {version: "0.25.0", released_at: 3.months.ago, file_count: 58, total_size: 880_000_i64},
        {version: "0.26.0", released_at: 2.weeks.ago, file_count: 60, total_size: 900_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "jwt",
      description: "JSON Web Token implementation in Crystal.",
      repository_url: "https://github.com/crystal-community/jwt",
      versions: [
        {version: "1.5.0", released_at: 6.months.ago, file_count: 30, total_size: 500_000_i64},
        {version: "1.6.0", released_at: 1.month.ago, file_count: 32, total_size: 520_000_i64},
      ]
    )

    create_doc_with_versions(
      package_name: "spectator",
      description: "Feature-rich spec testing framework for Crystal inspired by RSpec.",
      repository_url: "https://github.com/icy-arctic-fox/spectator",
      versions: [
        {version: "0.11.0", released_at: 5.months.ago, file_count: 88, total_size: 1_300_000_i64},
        {version: "0.12.0", released_at: 2.months.ago, file_count: 92, total_size: 1_350_000_i64},
      ]
    )
  end

  private def create_doc_with_versions(package_name : String, description : String? = nil,
                                       repository_url : String? = nil,
                                       versions : Array(NamedTuple) = [] of NamedTuple)
    return if DocQuery.new.package_name(package_name).any?

    current_version = versions.last? ? versions.last[:version] : nil
    total_views = Random.rand(100..50000).to_i64

    doc = SaveDoc.create!(
      package_name: package_name,
      current_version: current_version,
      description: description,
      repository_url: repository_url,
      total_views: total_views,
      last_updated_at: Time.utc
    )

    versions.each do |version_data|
      version = version_data[:version].as(String)

      # Upload real content and record what was actually written. Seeding
      # build_status "success" with invented file counts, as this task used
      # to, left every version page reporting that documentation was
      # unavailable because nothing had ever been stored.
      written = upload_placeholder_docs(package_name, version, description)

      SaveDocVersion.create!(
        doc_id: doc.id,
        version: version,
        published_at: version_data[:released_at].as(Time),
        build_status: written.nil? ? "failed" : "success",
        storage_path: "#{package_name}/#{version}",
        file_count: written.nil? ? 0 : written[:files],
        total_size: written.nil? ? 0_i64 : written[:bytes]
      )
    end

    puts "  Created documentation: #{package_name} with #{versions.size} versions"
  end

  # Writes a small but genuine documentation tree so the browser has something
  # real to serve. Returns nil when the store could not be reached.
  private def upload_placeholder_docs(package_name : String, version : String,
                                      description : String?) : NamedTuple(files: Int32, bytes: Int64)?
    return nil unless @storage_available

    pages = {
      "index.html"     => index_page(package_name, version, description),
      "api/index.html" => api_page(package_name, version),
    }

    files = 0
    bytes = 0_i64

    pages.each do |path, content|
      written = @storage.upload_doc_file(package_name, version, path, content)
      return nil if written.nil?

      files += 1
      bytes += written
    end

    {files: files, bytes: bytes}
  end

  private def index_page(package_name : String, version : String, description : String?) : String
    <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="utf-8"><title>#{package_name} #{version}</title></head>
    <body>
      <h1>#{package_name} <small>#{version}</small></h1>
      <p>#{description || "Crystal shard documentation."}</p>
      <p>This is sample documentation generated by the development seed.</p>
      <ul><li><a href="api/index.html">API reference</a></li></ul>
    </body>
    </html>
    HTML
  end

  private def api_page(package_name : String, version : String) : String
    <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="utf-8"><title>#{package_name} #{version} API</title></head>
    <body>
      <h1>API reference</h1>
      <p>Sample API documentation for #{package_name} #{version}.</p>
      <p><a href="../index.html">Back to overview</a></p>
    </body>
    </html>
    HTML
  end
end
