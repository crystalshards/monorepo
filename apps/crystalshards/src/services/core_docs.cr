require "../../config/object_store"
require "json"
require "./docs_sandbox"
require "./docs_build_status"
require "./storage_service"
require "../docs_database"

module CrystalShards
  # Publishes the Crystal standard library's own documentation under the
  # package name `PACKAGE`, through the same pipeline every other package's
  # documentation goes through: a sandboxed `crystal docs` compile, a
  # validated artifact, one object in the docs bucket, and rows in the
  # crystaldocs database that say the version is built.
  #
  # It is not a shard, and is handled as one nowhere in this module. Nobody
  # depends on the Crystal repository the way they depend on a shard, there is
  # no shard.yml to read a name or version out of, and it is never resolved
  # from the registry: `BuildDocsWorker` recognises `PACKAGE` before it ever
  # touches `ShardQuery`, so nothing a shard author publishes can reach this
  # code path. See CrystalDocs::DependencyIndex::CORE_PACKAGE, TypeLinker and
  # CrystalStorage::Keys on the crystaldocs side: all three already assume
  # this bare key names the standard library, which is why it is not renamed
  # here.
  #
  # `REPOSITORY` is a constant with no environment override, deliberately.
  # Selection of what to clone and compile has to be a fact fixed at compile
  # time of THIS codebase, not data a caller supplies, because unlike a shard
  # build the untrusted phase runs against source nobody sandboxed a
  # reputation check on: it is trusted because it is Crystal's own official
  # repository at a pinned tag, and that trust is only defensible while
  # nothing at runtime can substitute a different URL. Making it configurable
  # would turn a reasoned exception into an arbitrary code execution switch.
  module CoreDocs
    PACKAGE      = "crystal"
    REPOSITORY   = "https://github.com/crystal-lang/crystal.git"
    DESCRIPTION  = "The Crystal standard library"
    CRYSTAL_PATH = "lib:src"
    ENTRY_FILE   = "src/docs_main.cr"
    PROJECT_NAME = "Crystal"

    # The Cloud Run Job env var docs-launcher points `CloudRunJobDocsSandbox`
    # at for this build. A distinct name from `CloudRunJobDocsSandbox::JOB_ENV`
    # so the two Jobs can never resolve to the same execution target by a
    # missing override: docs-build-core carries the extra llvm-dev/llvm-static
    # packages docs-build does not, and must never run a stranger's shard.
    JOB_ENV = "DOCS_BUILD_CORE_JOB"

    def self.package?(name : String) : Bool
      name == PACKAGE
    end

    # The compiler this process is going to build with, and therefore the
    # only version of the standard library it may build.
    #
    # There is exactly one version in play here, not two. A shard build
    # resolves a SHARD version from the registry and a COMPILER version from
    # the sandbox image, and the two are independent facts. The standard
    # library has no such split: the artifact IS the documentation of the
    # exact source tree the compiler doing the compiling was built from, so
    # asking for any version other than the one that will actually run the
    # compile would mean compiling one release's source with a different
    # release's compiler, which is not a smaller version of the same mistake
    # a shard build guards against, it is that exact mistake with nothing
    # left to catch it. This is why the version is read from the sandbox
    # rather than threaded through as configuration: whoever changes the
    # sandbox image changes this, in one place, by definition.
    #
    # Mode aware for the same reason `UnsandboxedDocsSandbox#crystal_version`
    # overrides the base class instead of inheriting it: `DocsSandbox.crystal_version`
    # reads a version out of DOCS_SANDBOX_IMAGE, which names a Cloud Run
    # image tag that does not exist when nothing is sandboxed. Unsandboxed,
    # the compiler doing the work is whatever `crystal` resolves to on this
    # machine, so that and not an unrelated image tag is the fact this
    # compares the requested version against.
    def self.version : String
      case ENV.fetch("DOCS_SANDBOX", "").downcase
      when "cloudrun"
        DocsSandbox.crystal_version
      else
        Crystal::VERSION
      end
    end

    class VersionMismatch < Exception
      def initialize(requested : String, compiler : String)
        super(
          "asked to build the standard library at #{requested.inspect}, but this sandbox compiles " \
          "with #{compiler.inspect} (from DocsSandbox.crystal_version). The artifact would describe " \
          "one release while being compiled by another, so the request is refused rather than honoured " \
          "against the wrong compiler."
        )
      end
    end

    class BuildFailed < Exception
    end

    # A core artifact that parses and is merely missing the types every other
    # package's cross links most depend on would fail silently: every link to
    # `Array`, `String`, `HTTP::Server` and the rest would quietly render as
    # plain text instead of a broken link anyone would notice. So this is
    # checked before publishing, not left to be discovered on a documentation
    # page. The list matches scripts/build_core_docs.sh's proven check.
    REQUIRED_TYPES = [
      "Array", "String", "Hash", "Int32", "IO", "Enumerable",
      "Comparable", "Indexable::Mutable", "HTTP::Server", "JSON::Any",
    ]

    class IncompleteArtifact < Exception
      def initialize(missing : Array(String))
        super("the artifact is missing #{missing.join(", ")}, which would turn every core cross link " \
              "naming one of them into plain text with nothing to say why")
      end
    end

    # Parses `docs_json_path` and confirms it names every type in
    # `REQUIRED_TYPES`, raising `IncompleteArtifact` otherwise. Returns the
    # number of distinct types found, for reporting.
    def self.validate!(docs_json_path : String) : Int32
      document = JSON.parse(File.read(docs_json_path))
      names = Set(String).new
      collect_type_names(document["program"]?.try(&.["types"]?), names)

      missing = REQUIRED_TYPES.reject { |name| names.includes?(name) }
      raise IncompleteArtifact.new(missing) unless missing.empty?

      names.size
    end

    private def self.collect_type_names(types : JSON::Any?, names : Set(String)) : Nil
      types.try(&.as_a?).try &.each do |type|
        full_name = type["full_name"]?.try(&.as_s?)
        next unless full_name
        # A generic type's full_name carries its parameters, e.g.
        # "Array(T)"; TypeLinker and the required-types check both key on
        # the bare name, so the parameter list is stripped the same way
        # scripts/build_core_docs.sh's check already did.
        names << full_name.split('(').first.strip
        collect_type_names(type["types"]?, names)
      end
    end

    # Registers the rows a documentation page reads to decide a version is
    # buildable at all, the same two rows `CrystalDocs::PackageRegistration`
    # writes for a shard the first time a reader opens its page.
    #
    # It cannot call that class: `PackageRegistration` takes a
    # `RegistryPackages::Package` and a `RegistryPackages::Release`, domain
    # objects this app's registry mirror produces and the standard library
    # has no registry entry to produce them from. This writes the same two
    # tables, in the same shape, over the same DOCS_DATABASE_URL connection
    # `DocsBuildStatus` already uses from this app, matching the exact insert
    # shape `spec/support/docs_rows.cr` already uses to set up this state in
    # specs. It is the equivalent, not a second mechanism: the columns, the
    # conflict targets and the 'pending' starting state are identical, and
    # everything after registration flows through the unmodified
    # `DocsBuildStatus`.
    #
    # Idempotent. A second call for a version already registered updates
    # nothing but `docs.current_version`, predicated on it having drifted.
    module Registration
      INSERT_DOC_SQL = <<-SQL
        INSERT INTO docs
          (package_name, current_version, description, repository_url, total_views, created_at, updated_at)
        VALUES ($1, $2, $3, $4, 0, $5, $5)
        ON CONFLICT (package_name) DO NOTHING
        SQL

      # The default version is corrected on sight, exactly as
      # PackageRegistration does for a shard's registry release: it is a fact
      # about which version this site should show by default, not something a
      # first registration should fix forever.
      UPDATE_CURRENT_VERSION_SQL = <<-SQL
        UPDATE docs
        SET current_version = $2, updated_at = $3
        WHERE package_name = $1
          AND current_version IS DISTINCT FROM $2
        SQL

      # doc_id resolved with a subselect rather than a second round trip
      # reading it back, the same shape spec/support/docs_rows.cr already
      # uses to set up this exact state in specs.
      INSERT_VERSION_SQL = <<-SQL
        INSERT INTO doc_versions
          (doc_id, version, published_at, build_status, storage_path, created_at, updated_at)
        SELECT id, $2, $3, 'pending', $4, $3, $3
        FROM docs
        WHERE package_name = $1
        ON CONFLICT (doc_id, version) DO NOTHING
        SQL

      def self.ensure!(version : String) : Nil
        now = Time.utc

        DocsDatabase.exec(INSERT_DOC_SQL, PACKAGE, version, DESCRIPTION, REPOSITORY, now)
        DocsDatabase.exec(UPDATE_CURRENT_VERSION_SQL, PACKAGE, version, now)
        DocsDatabase.exec(INSERT_VERSION_SQL, PACKAGE, version, now, "#{PACKAGE}/#{version}")
      end
    end

    record Published, key : String, bytes : Int64, types : Int32, reused_existing : Bool

    # Builds and publishes one version of the standard library end to end:
    # register, compile under whichever sandbox this process is configured
    # for, validate, upload, and record the outcome. The same four steps and
    # the same two refusals (build produced nothing usable; build produced
    # something incomplete) scripts/build_core_docs.sh proved by hand,
    # running here instead of on a developer's laptop, and reachable in
    # production through the same docs-launcher and BuildDocsWorker path
    # every shard's documentation already goes through, never a second one.
    #
    # Raises on any failure, after recording it through DocsBuildStatus, the
    # same contract BuildDocsWorker's own rescue clauses rely on for a shard.
    def self.build_and_publish(
      version : String = self.version,
      storage : DocsStorage = StorageService.build,
    ) : Published
      compiler = self.version
      raise VersionMismatch.new(version, compiler) unless version == compiler

      Registration.ensure!(version)
      status = DocsBuildStatus.new(PACKAGE, version)
      key = CrystalStorage::Keys.docs_json(PACKAGE, version)

      # The bootstrap is one artifact, not one row. A row saying success is not
      # evidence the page can render; that is the exact gap the reconciliation
      # binary exists to repair. If the artifact is already there, though, then
      # the build is already done and this run is a no-op: mark the row
      # succeeded again so the database catches up with the bucket, and return
      # without spending a clone and a compile on bytes this site already has.
      if CrystalStorage.docs.exists?(key)
        status.succeeded
        Log.info { "CoreDocs: #{key} already exists, skipped rebuilding" }
        return Published.new(key: key, bytes: 0_i64, types: 0, reused_existing: true)
      end

      status.building

      work_dir = File.tempname("core_docs")
      Dir.mkdir_p(work_dir)

      begin
        source_dir = File.join(work_dir, "crystal")
        docs_dir = File.join(work_dir, "docs")

        clone(version, source_dir)
        docs_json = compile(source_dir, docs_dir, version)
        types = validate!(docs_json)
        bytes = File.size(docs_json)

        key = storage.upload_docs_json(PACKAGE, version, docs_json)
        status.succeeded

        Log.info { "CoreDocs: published #{PACKAGE}@#{version} to #{key} (#{bytes} bytes, #{types} types)" }
        Published.new(key: key, bytes: bytes.to_i64, types: types, reused_existing: false)
      rescue ex : DocsBuildStatus::Unrecorded
        # The outcome, whatever it was, could not be written down. Recording
        # 'failed' over the same connection cannot work and would be a lie if
        # it did; DocsBuildStatus has already logged this against the
        # package and version. Raising is what a redelivered request needs
        # in order to try again.
        raise ex
      rescue ex : Exception
        begin
          status.failed(ex.message)
        rescue DocsBuildStatus::Unrecorded
          # Already logged there.
        end
        raise ex
      ensure
        FileUtils.rm_rf(work_dir) if Dir.exists?(work_dir)
      end
    end

    # A checkout that cannot reach the requested tag is fatal, matching
    # DocsBuilder's own rule for a shard: publishing an artifact under a
    # version's name that it was not built from is worse than publishing
    # nothing.
    private def self.clone(version : String, target_dir : String) : Nil
      output = IO::Memory.new
      status = Process.run(
        "git",
        ["clone", "--depth", "1", "--branch", version, "--quiet", REPOSITORY, target_dir],
        output: output,
        error: output
      )

      raise BuildFailed.new("could not clone #{REPOSITORY} at tag #{version}: #{output}") unless status.success?
    end

    # Compiles `source_dir` into `docs_dir/docs.json`, through whichever
    # sandbox `DOCS_SANDBOX` selects. `docker` is not offered here: the
    # sandbox image carries no LLVM, and giving the untrusted-shard sandbox
    # image the packages this build needs is exactly the coupling
    # docs-build-core exists to avoid. A local rehearsal uses `none` with
    # DOCS_SANDBOX_ALLOW_UNSAFE=true, which runs on this machine's own
    # `crystal`, the same way scripts/build_core_docs.sh always has.
    private def self.compile(source_dir : String, docs_dir : String, version : String) : String
      Dir.mkdir_p(docs_dir)
      sandbox = resolve_sandbox(version)

      ok = sandbox ? sandbox.build_docs(source_dir, docs_dir) : compile_unsandboxed(source_dir, docs_dir, version)
      docs_json = File.join(docs_dir, DocsSandbox::DOCS_JSON)

      unless ok && DocsSandbox.valid_docs_json?(docs_json)
        reason = sandbox.try(&.failure_reason)
        raise BuildFailed.new(reason || "crystal docs produced no usable #{DocsSandbox::DOCS_JSON}")
      end

      docs_json
    end

    private def self.resolve_sandbox(version : String) : DocsSandbox?
      case ENV.fetch("DOCS_SANDBOX", "").downcase
      when "cloudrun"
        CloudRunJobDocsSandbox.new(
          job_env: JOB_ENV,
          crystal_path: CRYSTAL_PATH,
          entry_file: ENTRY_FILE,
          project_name: PROJECT_NAME,
          project_version: version,
        )
      when "none", ""
        unless ENV["DOCS_SANDBOX_ALLOW_UNSAFE"]? == "true"
          raise DocsSandbox::Unavailable.new(
            "Refusing to build the standard library documentation without a sandbox. This still " \
            "compiles Crystal's own macros, including llvm.cr shelling out to llvm-config. Set " \
            "DOCS_SANDBOX=cloudrun in production, or DOCS_SANDBOX_ALLOW_UNSAFE=true for local " \
            "development only."
          )
        end
        nil
      else
        raise DocsSandbox::Unavailable.new(
          "Unknown DOCS_SANDBOX #{ENV["DOCS_SANDBOX"]?.inspect} for the standard library. Expected " \
          "cloudrun or none; docker is not offered here because that image carries no LLVM."
        )
      end
    end

    # The exact recipe scripts/build_core_docs.sh proved: CRYSTAL_PATH must
    # name the CLONE's own src and lib, not the installed compiler's, or the
    # standard library loads twice and the build dies on "already initialized
    # constant Array::SMALL_ARRAY_SIZE". --project-name and --project-version
    # are required because the Crystal repository has no shard.yml to infer
    # them from.
    private def self.compile_unsandboxed(source_dir : String, docs_dir : String, version : String) : Bool
      Log.warn { "CoreDocs: building the standard library with no sandbox. Local development only." }

      docs_json = File.join(docs_dir, DocsSandbox::DOCS_JSON)
      error = IO::Memory.new

      status = File.open(docs_json, "w") do |stdout|
        Process.run(
          "crystal",
          [
            "docs", "--format=json",
            "--project-name=#{PROJECT_NAME}",
            "--project-version=#{version}",
            ENTRY_FILE,
          ],
          chdir: source_dir,
          env: {"CRYSTAL_PATH" => CRYSTAL_PATH},
          output: stdout,
          error: error
        )
      end

      unless status.success?
        Log.error { "CoreDocs: crystal docs failed: #{error.to_s.lines.last(20).join('\n')}" }
        File.delete(docs_json) if File.exists?(docs_json)
      end

      status.success?
    end
  end
end
