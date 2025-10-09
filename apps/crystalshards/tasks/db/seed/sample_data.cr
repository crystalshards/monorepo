class Db::Seed::SampleData < LuckyTask::Task
  summary "Add sample database records helpful for development"

  def call
    seed_popular_shards
    puts "Done adding sample data"
  end

  private def seed_popular_shards
    puts "Seeding popular Crystal shards..."

    create_shard_with_versions(
      name: "lucky",
      description: "A full-featured Crystal web framework that catches bugs for you, runs incredibly fast, and helps you write code that lasts.",
      repository_url: "https://github.com/luckyframework/lucky",
      homepage_url: "https://luckyframework.org",
      documentation_url: "https://luckyframework.org/guides",
      license: "MIT",
      github_stars: 2500,
      github_forks: 150,
      versions: [
        {version: "0.28.0", released_at: 2.months.ago, crystal_version: "1.0.0"},
        {version: "0.29.0", released_at: 1.month.ago, crystal_version: "1.1.0"},
        {version: "1.0.0", released_at: 1.week.ago, crystal_version: "1.2.0"},
      ]
    )

    create_shard_with_versions(
      name: "kemal",
      description: "Lightning Fast, Super Simple web framework for Crystal. Inspired by Sinatra.",
      repository_url: "https://github.com/kemalcr/kemal",
      homepage_url: "https://kemalcr.com",
      documentation_url: "https://kemalcr.com/guide",
      license: "MIT",
      github_stars: 3500,
      github_forks: 250,
      versions: [
        {version: "1.2.0", released_at: 6.months.ago, crystal_version: "1.0.0"},
        {version: "1.3.0", released_at: 3.months.ago, crystal_version: "1.1.0"},
        {version: "1.4.0", released_at: 2.weeks.ago, crystal_version: "1.2.0"},
      ]
    )

    create_shard_with_versions(
      name: "amber",
      description: "A Crystal web framework that makes building applications fast, simple, and enjoyable.",
      repository_url: "https://github.com/amberframework/amber",
      homepage_url: "https://amberframework.org",
      documentation_url: "https://docs.amberframework.org",
      license: "MIT",
      github_stars: 2000,
      github_forks: 180,
      versions: [
        {version: "1.2.0", released_at: 4.months.ago, crystal_version: "1.0.0"},
        {version: "1.3.0", released_at: 1.month.ago, crystal_version: "1.1.0"},
      ]
    )

    create_shard_with_versions(
      name: "granite",
      description: "ORM for Crystal. Inspired by ActiveRecord and Ecto.",
      repository_url: "https://github.com/amberframework/granite",
      homepage_url: "https://amberframework.org/granite",
      license: "MIT",
      github_stars: 500,
      github_forks: 80,
      versions: [
        {version: "0.23.0", released_at: 5.months.ago, crystal_version: "1.0.0"},
        {version: "0.24.0", released_at: 2.months.ago, crystal_version: "1.1.0"},
        {version: "0.25.0", released_at: 2.weeks.ago, crystal_version: "1.2.0"},
      ]
    )

    create_shard_with_versions(
      name: "jennifer",
      description: "Active Record pattern implementation for Crystal with flexible query chainable builder and migration system.",
      repository_url: "https://github.com/imdrasil/jennifer.cr",
      documentation_url: "https://imdrasil.github.io/jennifer.cr/docs",
      license: "MIT",
      github_stars: 400,
      github_forks: 45,
      versions: [
        {version: "0.11.0", released_at: 6.months.ago, crystal_version: "1.0.0"},
        {version: "0.12.0", released_at: 3.months.ago, crystal_version: "1.1.0"},
        {version: "0.13.0", released_at: 3.weeks.ago, crystal_version: "1.2.0"},
      ]
    )

    create_shard_with_versions(
      name: "ameba",
      description: "A static code analysis tool for Crystal. Helps maintain code quality and consistency.",
      repository_url: "https://github.com/crystal-ameba/ameba",
      license: "MIT",
      github_stars: 450,
      github_forks: 50,
      versions: [
        {version: "1.4.0", released_at: 4.months.ago, crystal_version: "1.0.0"},
        {version: "1.5.0", released_at: 1.month.ago, crystal_version: "1.1.0"},
      ]
    )

    create_shard_with_versions(
      name: "spec-kemal",
      description: "Easy testing for Kemal applications.",
      repository_url: "https://github.com/kemalcr/spec-kemal",
      license: "MIT",
      github_stars: 150,
      github_forks: 25,
      versions: [
        {version: "1.0.0", released_at: 8.months.ago, crystal_version: "1.0.0"},
        {version: "1.1.0", released_at: 2.months.ago, crystal_version: "1.1.0"},
      ]
    )

    create_shard_with_versions(
      name: "crystal-redis",
      description: "Full featured Redis client for Crystal.",
      repository_url: "https://github.com/stefanwille/crystal-redis",
      license: "MIT",
      github_stars: 350,
      github_forks: 60,
      versions: [
        {version: "2.8.0", released_at: 5.months.ago, crystal_version: "1.0.0"},
        {version: "2.9.0", released_at: 1.month.ago, crystal_version: "1.1.0"},
      ]
    )

    create_shard_with_versions(
      name: "crystal-pg",
      description: "PostgreSQL driver for Crystal.",
      repository_url: "https://github.com/will/crystal-pg",
      license: "BSD-3-Clause",
      github_stars: 420,
      github_forks: 75,
      versions: [
        {version: "0.24.0", released_at: 7.months.ago, crystal_version: "1.0.0"},
        {version: "0.25.0", released_at: 3.months.ago, crystal_version: "1.1.0"},
        {version: "0.26.0", released_at: 2.weeks.ago, crystal_version: "1.2.0"},
      ]
    )

    create_shard_with_versions(
      name: "http-client-digest_auth",
      description: "HTTP Digest authentication support for Crystal's HTTP::Client.",
      repository_url: "https://github.com/spider-gazelle/http-client-digest_auth",
      license: "MIT",
      github_stars: 25,
      github_forks: 5,
      versions: [
        {version: "1.0.0", released_at: 1.year.ago, crystal_version: "1.0.0"},
        {version: "1.1.0", released_at: 3.months.ago, crystal_version: "1.1.0"},
      ]
    )

    create_shard_with_versions(
      name: "jwt",
      description: "JSON Web Token implementation in Crystal.",
      repository_url: "https://github.com/crystal-community/jwt",
      license: "MIT",
      github_stars: 200,
      github_forks: 35,
      versions: [
        {version: "1.5.0", released_at: 6.months.ago, crystal_version: "1.0.0"},
        {version: "1.6.0", released_at: 1.month.ago, crystal_version: "1.1.0"},
      ]
    )

    create_shard_with_versions(
      name: "spectator",
      description: "Feature-rich spec testing framework for Crystal inspired by RSpec.",
      repository_url: "https://github.com/icy-arctic-fox/spectator",
      documentation_url: "https://icy-arctic-fox.github.io/spectator",
      license: "MIT",
      github_stars: 280,
      github_forks: 22,
      versions: [
        {version: "0.11.0", released_at: 5.months.ago, crystal_version: "1.0.0"},
        {version: "0.12.0", released_at: 2.months.ago, crystal_version: "1.1.0"},
      ]
    )
  end

  private def create_shard_with_versions(name : String, description : String, repository_url : String,
                                         homepage_url : String? = nil, documentation_url : String? = nil,
                                         license : String? = nil, github_stars : Int32? = nil,
                                         github_forks : Int32? = nil, versions : Array(NamedTuple) = [] of NamedTuple)
    return if ShardQuery.new.name(name).any?

    total_downloads = versions.size * Random.rand(100..10000).to_i64

    shard = SaveShard.create!(
      name: name,
      description: description,
      repository_url: repository_url,
      homepage_url: homepage_url,
      documentation_url: documentation_url,
      license: license,
      total_downloads: total_downloads,
      github_stars: github_stars,
      github_forks: github_forks,
      last_synced_at: Time.utc,
      provider: "github",
      repository_type: "git"
    )

    versions.each do |version_data|
      SaveShardVersion.create!(
        shard_id: shard.id,
        version: version_data[:version],
        yanked: false,
        released_at: version_data[:released_at],
        crystal_version: version_data[:crystal_version]?,
        commit_sha: Random::Secure.hex(20)
      )
    end

    puts "  Created shard: #{name} with #{versions.size} versions"
  end
end
