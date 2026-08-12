require "../spec_helper"

# `shards install` shells out to `crystal` once, after it has written the lock,
# only to learn the compiler version. The launcher image has no compiler in it,
# so that call fails and takes the whole install with it, having already done
# the work. Putting CRYSTAL_VERSION in its environment removes the call.
#
# The value has to be the one the sandbox will compile with. Dependencies
# resolved for one compiler and compiled by another is a mismatch nothing in
# the system would notice, so these pin that the version is read off the
# sandbox and never configured beside it.
private def with_image(value : String?, &)
  previous = ENV["DOCS_SANDBOX_IMAGE"]?

  if value
    ENV["DOCS_SANDBOX_IMAGE"] = value
  else
    ENV.delete("DOCS_SANDBOX_IMAGE")
  end

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

describe CrystalShards::DocsSandbox do
  describe ".crystal_version" do
    it "reads the version out of the configured image" do
      with_image("crystallang/crystal:1.20.3-alpine") do
        CrystalShards::DocsSandbox.crystal_version.should eq("1.20.3")
      end
    end

    it "matches the default image, so the two cannot drift apart" do
      with_image(nil) do
        CrystalShards::DocsSandbox.crystal_version.should eq(
          CrystalShards::DocsSandbox::DEFAULT_IMAGE.split(':').last.split('-').first
        )
      end
    end

    it "accepts a tag without a suffix and one with a v" do
      with_image("crystallang/crystal:1.21.0") do
        CrystalShards::DocsSandbox.crystal_version.should eq("1.21.0")
      end

      with_image("crystallang/crystal:v1.21.0-alpine3.20") do
        CrystalShards::DocsSandbox.crystal_version.should eq("1.21.0")
      end
    end

    # A registry host carries a port and it looks exactly like a tag. Reading
    # the whole string finds the port's digits and reports a version this
    # build will never use, which is the failure that would be hardest to
    # notice: dependencies resolved for a compiler nobody chose.
    it "reads the tag, not a registry port that resembles one" do
      with_image("registry.internal:1.2.3/crystallang/crystal:1.21.0-alpine") do
        CrystalShards::DocsSandbox.crystal_version.should eq("1.21.0")
      end
    end

    it "refuses a registry port when the image itself has no version tag" do
      with_image("registry.internal:1.2.3/crystallang/crystal:latest") do
        expect_raises(CrystalShards::DocsSandbox::UnreadableImageVersion, /latest/) do
          CrystalShards::DocsSandbox.crystal_version
        end
      end
    end

    # Guessing is the one thing that must not happen: a wrong version resolves
    # the wrong dependencies and nothing downstream can tell.
    it "refuses an image pinned only by digest" do
      with_image("crystallang/crystal@sha256:0000000000000000000000000000000000000000000000000000000000000000") do
        expect_raises(CrystalShards::DocsSandbox::UnreadableImageVersion) do
          CrystalShards::DocsSandbox.crystal_version
        end
      end
    end

    it "refuses a partial version and a missing tag" do
      with_image("crystallang/crystal:1.21") do
        expect_raises(CrystalShards::DocsSandbox::UnreadableImageVersion) do
          CrystalShards::DocsSandbox.crystal_version
        end
      end

      with_image("crystallang/crystal") do
        expect_raises(CrystalShards::DocsSandbox::UnreadableImageVersion) do
          CrystalShards::DocsSandbox.crystal_version
        end
      end
    end

    it "names both the setting and a usable value when it refuses" do
      with_image("crystallang/crystal:nightly") do
        expect_raises(
          CrystalShards::DocsSandbox::UnreadableImageVersion,
          /DOCS_SANDBOX_IMAGE.*crystallang\/crystal:1\.21\.0-alpine/m
        ) do
          CrystalShards::DocsSandbox.crystal_version
        end
      end
    end
  end

  describe "#crystal_version" do
    it "comes from the sandbox that will run the compile" do
      with_image("crystallang/crystal:1.20.3-alpine") do
        CrystalShards::DockerDocsSandbox.new.crystal_version.should eq("1.20.3")
      end
    end

    # The unsandboxed path runs `crystal` off PATH and never pulls the image,
    # so answering with the image tag would be resolving dependencies for a
    # compiler that is not the one about to run.
    it "ignores the image when no image is used" do
      with_image("crystallang/crystal:1.20.3-alpine") do
        CrystalShards::UnsandboxedDocsSandbox.new.crystal_version.should eq(Crystal::VERSION)
      end
    end
  end
end
