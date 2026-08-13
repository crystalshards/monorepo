require "../spec_helper"

# What is fast and pure enough to run on every spec suite: recognising the
# package, resolving which version this process may build, registering rows,
# and refusing an artifact that parses but is incomplete.
#
# `CoreDocs.build_and_publish`'s clone-and-compile path is deliberately not
# exercised here. It shells out to `git` and `crystal docs` against the real
# Crystal repository, which needs network, minutes, and (unsandboxed) a
# working LLVM toolchain on whatever machine runs the suite — none of which
# belongs in a spec that has to be fast, hermetic, and safe on every run.
# That path is proven by running scripts/build_core_docs.sh for real; see the
# PR description for a recorded run: a real clone, a real compile, a
# published artifact whose size and type count are reported, an artifact
# refused for missing a required type without publishing anything, and the
# database rows changing through CrystalShards::DocsBuildStatus exactly as a
# shard build's do.
private def with_docs_sandbox(value : String?, &)
  previous = ENV["DOCS_SANDBOX"]?

  if value
    ENV["DOCS_SANDBOX"] = value
  else
    ENV.delete("DOCS_SANDBOX")
  end

  begin
    yield
  ensure
    if previous
      ENV["DOCS_SANDBOX"] = previous
    else
      ENV.delete("DOCS_SANDBOX")
    end
  end
end

private def with_image(value : String, &)
  previous = ENV["DOCS_SANDBOX_IMAGE"]?
  ENV["DOCS_SANDBOX_IMAGE"] = value

  begin
    yield
  ensure
    if previous
      ENV["DOCS_SANDBOX_IMAGE"] = previous
    else
      ENV.delete("DOCS_SANDBOX_IMAGE")
    end
  end
end

# A minimal `crystal docs --format=json` document: a `program.types` array of
# objects carrying `full_name` and, for the ones with nested members, their
# own `types`. Only the two fields CoreDocs.validate! reads are populated.
private def fixture_docs_json(*, named type_names : Array(String)) : String
  types = type_names.map { |name| {"full_name" => name, "types" => [] of String} }
  {"program" => {"types" => types}}.to_json
end

private def write_fixture(content : String) : String
  path = File.tempname("core_docs_fixture", ".json")
  File.write(path, content)
  path
end

describe CrystalShards::CoreDocs do
  describe ".package?" do
    it "recognises the bare key and nothing else" do
      CrystalShards::CoreDocs.package?("crystal").should be_true
      CrystalShards::CoreDocs.package?("github.com/crystal-lang/crystal").should be_false
      CrystalShards::CoreDocs.package?("crystal-lang/crystal").should be_false
      CrystalShards::CoreDocs.package?("Crystal").should be_false
    end
  end

  describe ".version" do
    it "reads the compiler version out of the configured sandbox image in cloudrun mode" do
      with_docs_sandbox("cloudrun") do
        with_image("crystallang/crystal:1.20.3-alpine") do
          CrystalShards::CoreDocs.version.should eq("1.20.3")
        end
      end
    end

    # Unsandboxed, there is no image: the compiler doing the compile is
    # whatever `crystal` resolves to on this machine, the same fact
    # UnsandboxedDocsSandbox#crystal_version already reports for a shard
    # build. Reading the image tag here instead would validate the request
    # against a compiler that is not the one about to run.
    it "reads Crystal::VERSION when nothing is sandboxed, ignoring any configured image" do
      with_docs_sandbox("none") do
        with_image("crystallang/crystal:1.20.3-alpine") do
          CrystalShards::CoreDocs.version.should eq(Crystal::VERSION)
        end
      end

      with_docs_sandbox(nil) do
        CrystalShards::CoreDocs.version.should eq(Crystal::VERSION)
      end
    end
  end

  describe ".build_and_publish" do
    # This is the one behaviour of build_and_publish a spec can pin without a
    # network or a compiler: the version check runs before Registration,
    # before DocsBuildStatus, before anything is cloned. A caller asking for
    # 9.9.9 out of a sandbox that will compile something else is refused
    # immediately, not partway through a build that could never have
    # succeeded.
    it "refuses a version that does not match the compiler before touching anything" do
      with_docs_sandbox("none") do
        expect_raises(
          CrystalShards::CoreDocs::VersionMismatch,
          /9\.9\.9.*#{Regex.escape(Crystal::VERSION)}/m
        ) do
          CrystalShards::CoreDocs.build_and_publish("9.9.9")
        end
      end

      # Nothing was registered: the version row this would have created,
      # for a version nobody is ever going to build, simply does not exist.
      DocsDatabase.query_one(
        "SELECT count(*) FROM doc_versions v JOIN docs d ON d.id = v.doc_id " \
        "WHERE d.package_name = 'crystal' AND v.version = '9.9.9'",
        as: Int64
      ).should eq(0)
    end
  end

  describe CrystalShards::CoreDocs::Registration do
    it "registers a pending version for a package with no prior documentation" do
      CrystalShards::CoreDocs::Registration.ensure!("1.99.0")

      DocsRows.version_status("crystal", "1.99.0").should eq("pending")
    end

    it "sets current_version to the version just registered" do
      CrystalShards::CoreDocs::Registration.ensure!("1.99.1")

      DocsDatabase.query_one(
        "SELECT current_version FROM docs WHERE package_name = 'crystal'",
        as: String?
      ).should eq("1.99.1")
    end

    it "moves current_version forward on a later registration without duplicating the package" do
      CrystalShards::CoreDocs::Registration.ensure!("1.99.2")
      CrystalShards::CoreDocs::Registration.ensure!("1.99.3")

      DocsDatabase.query_one(
        "SELECT count(*) FROM docs WHERE package_name = 'crystal'", as: Int64
      ).should eq(1)
      DocsDatabase.query_one(
        "SELECT current_version FROM docs WHERE package_name = 'crystal'", as: String?
      ).should eq("1.99.3")
    end

    it "leaves a build_status a build already wrote alone on re-registration" do
      CrystalShards::CoreDocs::Registration.ensure!("1.99.4")
      DocsDatabase.exec(<<-SQL)
        UPDATE doc_versions SET build_status = 'success'
        WHERE version = '1.99.4' AND doc_id IN (SELECT id FROM docs WHERE package_name = 'crystal')
        SQL

      CrystalShards::CoreDocs::Registration.ensure!("1.99.4")

      DocsRows.version_status("crystal", "1.99.4").should eq("success")
    end
  end

  describe ".validate!" do
    it "returns the number of distinct types when every required type is present" do
      path = write_fixture(fixture_docs_json(named: CrystalShards::CoreDocs::REQUIRED_TYPES + ["Foo::Bar"]))

      CrystalShards::CoreDocs.validate!(path).should eq(CrystalShards::CoreDocs::REQUIRED_TYPES.size + 1)
    end

    it "raises, naming exactly what is missing, when a required type is absent" do
      present = CrystalShards::CoreDocs::REQUIRED_TYPES - ["HTTP::Server", "JSON::Any"]
      path = write_fixture(fixture_docs_json(named: present))

      expect_raises(CrystalShards::CoreDocs::IncompleteArtifact, /HTTP::Server.*JSON::Any/) do
        CrystalShards::CoreDocs.validate!(path)
      end
    end

    it "strips generic parameters before matching a full_name against the required list" do
      path = write_fixture(fixture_docs_json(named: CrystalShards::CoreDocs::REQUIRED_TYPES.map { |name| "#{name}(T)" }))

      CrystalShards::CoreDocs.validate!(path).should eq(CrystalShards::CoreDocs::REQUIRED_TYPES.size)
    end

    it "finds a required type nested under another, and counts the wrapper too" do
      nested = {
        "program" => {
          "types" => [
            {
              "full_name" => "HTTP",
              "types" => CrystalShards::CoreDocs::REQUIRED_TYPES.map { |name| {"full_name" => name} },
            },
          ],
        },
      }.to_json
      path = write_fixture(nested)

      # 1 for the "HTTP" wrapper itself, plus one per required type nested
      # inside it: collect_type_names records every level it walks, not only
      # the leaves, so a required type does not have to be top level to be
      # found.
      CrystalShards::CoreDocs.validate!(path).should eq(CrystalShards::CoreDocs::REQUIRED_TYPES.size + 1)
    end

    # Safe navigation, not a hard crash: a document missing "program" or
    # "types" entirely walks zero types rather than raising KeyError, so it
    # is refused through the SAME path as a document that walked fine but
    # named none of the required types, naming every one of them missing.
    it "treats a document with no program.types as missing every required type" do
      path = write_fixture(%({"not_a_program_document": true}))

      expect_raises(CrystalShards::CoreDocs::IncompleteArtifact, /#{Regex.escape(CrystalShards::CoreDocs::REQUIRED_TYPES.first)}/) do
        CrystalShards::CoreDocs.validate!(path)
      end
    end
  end
end
