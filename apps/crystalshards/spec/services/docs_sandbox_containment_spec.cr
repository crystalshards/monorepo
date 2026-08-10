require "../spec_helper"

# Proves the confinement, rather than asserting that we configured flags.
#
# The fixture below is a working shard whose macros try, at compile time, to
# read a credential out of the environment, reach the network, read a file on
# the host that was never handed to the build, and write outside the one
# directory the build is meant to produce. That is not contrived: a top-level
# `{% \`...\` %}` runs while `crystal docs` compiles, so anything published to
# the registry can do this.
#
# Skipped when docker is unavailable, because the point is to exercise the real
# boundary and a mocked one would prove nothing.
private def docker_available? : Bool
  Process.run("docker", ["info"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
rescue
  false
end

# `host_secret_path` is a real file on this machine that is deliberately NOT
# mounted into the sandbox, so reading it would be a genuine escape. `/out` is
# the build's own output mount and is expected to be writable, which is why the
# filesystem probe targets `/etc` instead.
private def hostile_source(host_secret_path : String) : String
  <<-CRYSTAL
  {% `printenv CANARY_CREDENTIAL > /out/env.txt 2>&1 || echo unreadable > /out/env.txt` %}
  {% `curl -s -m 3 -o /out/net.txt https://example.com || echo blocked > /out/net.txt` %}
  {% `id > /out/whoami.txt 2>&1` %}
  {% `cat #{host_secret_path} > /out/host_read.txt 2>&1 || echo unreachable > /out/host_read.txt` %}
  {% `touch /etc/escaped 2>/dev/null && echo WRITABLE > /out/rootfs.txt || echo readonly > /out/rootfs.txt` %}

  module Hostile
    # Something real to document, so a successful build is distinguishable
    # from a build that never ran.
    def self.greet : String
      "hello"
    end
  end
  CRYSTAL
end

describe "documentation sandbox containment" do
  it "denies a hostile shard the environment, the network and the host" do
    pending! "docker is not available" unless docker_available?

    source = File.tempname("hostile_src")
    output = File.tempname("hostile_out")
    host_only = File.tempname("host_only")

    Dir.mkdir_p(File.join(source, "src"))
    Dir.mkdir_p(output)
    Dir.mkdir_p(host_only)

    # A file on the host that the sandbox is never given. Reading it from
    # inside the build would mean the boundary leaks.
    host_secret_path = File.join(host_only, "host_secret.txt")
    File.write(host_secret_path, "host-file-must-not-be-readable")

    File.write(File.join(source, "shard.yml"), "name: hostile\nversion: 0.1.0\n")
    File.write(File.join(source, "src", "hostile.cr"), hostile_source(host_secret_path))

    # A credential in this process's environment, exactly as the worker holds
    # MINIO_SECRET_KEY. The build must not be able to see it.
    ENV["CANARY_CREDENTIAL"] = "canary-must-not-escape"

    begin
      built = CrystalShards::DockerDocsSandbox.new.build_docs(source, output)

      read = ->(name : String) {
        path = File.join(output, name)
        File.exists?(path) ? File.read(path).strip : ""
      }

      # The credential is the whole game: this is what an attacker publishes a
      # shard to steal.
      read.call("env.txt").should_not contain("canary-must-not-escape")

      # No egress, so nothing can be shipped out even if it were readable.
      read.call("net.txt").should eq("blocked")

      # A host file outside the mounts stays outside.
      read.call("host_read.txt").should_not contain("host-file-must-not-be-readable")

      # The container filesystem is read-only apart from the declared mounts.
      read.call("rootfs.txt").should eq("readonly")

      # Not root inside the container.
      read.call("whoami.txt").should contain("uid=1000")

      # The build ran and produced real documentation, so the confinement is
      # not passing merely by breaking the build.
      built.should be_true
      File.exists?(File.join(output, "index.html")).should be_true
      File.exists?(File.join(output, "Hostile.html")).should be_true
    ensure
      ENV.delete("CANARY_CREDENTIAL")
      FileUtils.rm_rf(source) if Dir.exists?(source)
      FileUtils.rm_rf(output) if Dir.exists?(output)
      FileUtils.rm_rf(host_only) if Dir.exists?(host_only)
    end
  end
end
