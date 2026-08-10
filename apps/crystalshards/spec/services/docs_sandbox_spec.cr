require "../spec_helper"

# Building documentation compiles code we did not write, and Crystal runs
# macros while compiling, so `crystal docs` on a published shard is arbitrary
# command execution. These specs pin the two things that keep that survivable:
# the selection rules refuse to build unconfined, and the confinement actually
# holds.
private def with_env(**vars, &)
  previous = {} of String => String?
  vars.each do |key, value|
    name = key.to_s
    previous[name] = ENV[name]?
    if value
      ENV[name] = value
    else
      ENV.delete(name)
    end
  end

  begin
    yield
  ensure
    previous.each do |name, value|
      if value
        ENV[name] = value
      else
        ENV.delete(name)
      end
    end
  end
end

describe CrystalShards::DocsSandbox do
  describe "choosing a sandbox" do
    it "refuses to build when no sandbox is configured" do
      with_env(DOCS_SANDBOX: nil, DOCS_SANDBOX_ALLOW_UNSAFE: nil) do
        expect_raises(CrystalShards::DocsSandbox::Unavailable, /Refusing to build/) do
          CrystalShards::DocsSandbox.build
        end
      end
    end

    it "still refuses when the escape hatch is not exactly true" do
      # Anything short of an explicit opt-in has to fail, or a stray value in a
      # deployment ends up silently running strangers' code next to secrets.
      with_env(DOCS_SANDBOX: "none", DOCS_SANDBOX_ALLOW_UNSAFE: "1") do
        expect_raises(CrystalShards::DocsSandbox::Unavailable) do
          CrystalShards::DocsSandbox.build
        end
      end
    end

    it "allows an unconfined build only when explicitly asked" do
      with_env(DOCS_SANDBOX: "none", DOCS_SANDBOX_ALLOW_UNSAFE: "true") do
        sandbox = CrystalShards::DocsSandbox.build
        sandbox.should be_a(CrystalShards::UnsandboxedDocsSandbox)
        # The description is what shows up in logs, so it must not read as safe.
        sandbox.description.should contain("NO SANDBOX")
      end
    end

    it "selects the docker sandbox" do
      with_env(DOCS_SANDBOX: "docker") do
        CrystalShards::DocsSandbox.build.should be_a(CrystalShards::DockerDocsSandbox)
      end
    end

    it "rejects an unrecognised setting rather than guessing" do
      with_env(DOCS_SANDBOX: "chroot") do
        expect_raises(CrystalShards::DocsSandbox::Unavailable, /Unknown DOCS_SANDBOX/) do
          CrystalShards::DocsSandbox.build
        end
      end
    end
  end

  describe "the builder refuses unconfined work" do
    it "does not clone anything when no sandbox is available" do
      # The refusal must happen for the whole build, not just the compile: a
      # build that clones first and fails later still burns network and disk.
      with_env(DOCS_SANDBOX: nil, DOCS_SANDBOX_ALLOW_UNSAFE: nil) do
        builder = CrystalShards::DocsBuilder.new

        expect_raises(CrystalShards::DocsSandbox::Unavailable) do
          builder.generate_docs("https://example.invalid/nope.git", "1.0.0", nil, "/tmp/never-used")
        end
      end
    end
  end
end
