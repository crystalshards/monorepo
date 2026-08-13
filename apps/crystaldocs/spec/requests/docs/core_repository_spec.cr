require "../../spec_helper"

# The Crystal repository is indexed like any other shard, and following it down
# the ordinary path produces a page that can never work.
#
# Documenting the standard library needs its own entrypoint, its own
# CRYSTAL_PATH and a toolchain the shard sandbox does not carry. Reproduced
# against the real image: a plain `crystal docs` at the repository root loads
# the library twice and dies on `already initialized constant
# Array::SMALL_ARRAY_SIZE`, and the corrected invocation then needs llvm-config,
# which is absent. So every attempt through the shard path fails, and in
# production the most important package on the site showed BUILD FAILED.
#
# It is also a second identity for something already published under
# CORE_PACKAGE, which is the key the storage layout, the type linker and every
# core cross link use. These redirects keep one identity.
describe "the Crystal repository's URLs" do
  it "sends the repository to the standard library" do
    response = BrowserClient.exec(
      Docs::Repositories::Show.with(host: "github.com", owner: "crystal-lang", repo: "crystal")
    )

    response.status_code.should eq(301)
    response.headers["Location"].should eq(
      CrystalDocs::PackagePaths.package_path(CrystalDocs::CORE_PACKAGE)
    )
  end

  it "keeps the version when one was asked for" do
    response = BrowserClient.exec(
      Docs::Repositories::Version.with(
        host: "github.com", owner: "crystal-lang", repo: "crystal", version: "1.21.0"
      )
    )

    response.status_code.should eq(301)
    response.headers["Location"].should eq(
      CrystalDocs::PackagePaths.version_path(CrystalDocs::CORE_PACKAGE, "1.21.0")
    )
  end

  # A link into a specific core type has to land on that type, not on the front
  # of the library, or every cross link into the standard library loses its
  it "carries the type through" do
    response = BrowserClient.exec(
      Lucky::RouteHelper.new(:get, "/docs/_/github.com/crystal-lang/crystal/1.21.0/HTTP/Handler")
    )

    response.status_code.should eq(301)
    response.headers["Location"].should eq(
      CrystalDocs::PackagePaths.type_path(CrystalDocs::CORE_PACKAGE, "1.21.0", "HTTP/Handler")
    )
  end

  # The match is a constant and must not be a pattern. A repository that merely
  # looks like the compiler's is somebody else's shard, and redirecting it to
  # the standard library would serve one project's documentation under another
  # project's name.
  it "does not claim a lookalike repository" do
    StubRegistryPackages.new
      .publish("github.com/someone/crystal", "crystal-fork", ["1.0.0"])
      .install

    response = BrowserClient.exec(
      Docs::Repositories::Show.with(host: "github.com", owner: "someone", repo: "crystal")
    )

    response.headers["Location"]?.should_not eq(
      CrystalDocs::PackagePaths.package_path(CrystalDocs::CORE_PACKAGE)
    )
  end
end
