module CrystalShards
  # The slice of object storage that documentation publishing depends on.
  # BuildDocsWorker talks to this rather than to StorageService directly, so a
  # spec can substitute a fake with no object store running.
  module DocsStorage
    abstract def upload_docs_json(shard_name : String, version : String, docs_json_path : String) : String
  end

  # The slice of object storage a sandboxed build depends on. Source goes in
  # and documentation comes back out through build-scoped scratch keys, which
  # is what lets the build stay unable to reach anything else.
  #
  # `scratch_signed_url` is the whole mechanism, not a convenience. The build
  # runs untrusted third-party shard code and therefore holds no credentials:
  # it reads its source from a signed GET and writes its output to a signed
  # PUT, both minted here, both scoped to one key the launcher chose. The build
  # cannot pick its own key, because the key is covered by the signature.
  module ScratchStorage
    abstract def upload_scratch(key : String, content : String)
    abstract def download_scratch(key : String) : String
    abstract def delete_scratch_prefix(prefix : String)
    abstract def scratch_signed_url(key : String, method : String, content_type : String? = nil) : String
  end

  # Package and documentation storage, over the `CrystalStorage` object store
  # interface: Google Cloud Storage in production, the local store in
  # development. Nothing here knows which.
  class StorageService
    include DocsStorage
    include ScratchStorage

    # How long a build has to use a URL it was handed. Long enough for a slow
    # `crystal docs` on a large shard, short enough that a leaked URL is not a
    # standing grant.
    SCRATCH_URL_TTL = 30.minutes

    # Test seams. When set, `build` returns this proc's result instead of a
    # real store-backed service. Always nil in production.
    class_property builder : Proc(DocsStorage)? = nil
    class_property scratch_builder : Proc(ScratchStorage)? = nil

    # Entry point for callers that only need the `DocsStorage` contract.
    def self.build : DocsStorage
      if custom = @@builder
        custom.call
      else
        new
      end
    end

    # Entry point for callers that need the `ScratchStorage` contract.
    def self.build_scratch : ScratchStorage
      if custom = @@scratch_builder
        custom.call
      else
        new
      end
    end

    def initialize(
      @packages : CrystalStorage::ObjectStore = CrystalStorage.packages,
      @docs : CrystalStorage::ObjectStore = CrystalStorage.docs,
    )
    end

    # Upload a published package tarball. Returns the object key.
    def upload_package_from_io(shard_name : String, version : String, content : String) : String
      key = CrystalStorage::Keys.package(shard_name, version)
      @packages.put(key, content, "application/gzip")
      key
    end

    # A URL a browser can follow to download a package.
    #
    # It has to be a signed URL rather than a public object path: the buckets
    # enforce uniform bucket level access with public access prevention, so
    # there is no such thing as a publicly readable object to link to.
    def package_download_url(shard_name : String, version : String, expires_in : Time::Span = 1.hour) : String
      @packages.signed_url(
        CrystalStorage::Keys.package(shard_name, version),
        method: "GET",
        expires_in: expires_in
      )
    end

    # Upload the generated documentation for a shard version. There is
    # exactly one artifact per version, the `crystal docs --format=json`
    # document. No generated HTML is ever stored: we render documentation
    # ourselves, and shard-authored markup served from our origin would be
    # stored XSS.
    # Returns the object key.
    def upload_docs_json(shard_name : String, version : String, docs_json_path : String) : String
      key = CrystalStorage::Keys.docs_json(shard_name, version)
      @docs.put(key, File.read(docs_json_path), "application/json")
      key
    end

    # Scratch space used to hand source into a sandboxed build and take
    # documentation back out. Keys are build-scoped, so nothing here is
    # durable.
    def upload_scratch(key : String, content : String)
      @docs.put(key, content, "application/gzip")
    end

    def download_scratch(key : String) : String
      @docs.get_string(key) || raise CrystalStorage::Unavailable.new(
        "find", key, "the build produced no object at this key"
      )
    end

    # Best effort, and deliberately so. The launcher identity holds
    # objectViewer and objectCreator on the docs bucket and nothing that grants
    # storage.objects.delete, because the only predefined role carrying delete
    # is objectAdmin, which would also let it erase published documentation.
    # So this 403s in production and that is the intended posture, not a
    # missing grant. Real cleanup is a bucket lifecycle rule on the
    # build-scratch prefix, which also collects scratch from an execution that
    # died before any ensure block could run. Failing a completed build over a
    # failed tidy-up would be the wrong trade.
    def delete_scratch_prefix(prefix : String)
      @docs.delete_prefix(prefix)
    rescue ex : CrystalStorage::Unavailable
      Log.info { "Scratch cleanup skipped for #{prefix}: #{ex.message}. The bucket lifecycle rule collects it." }
    end

    # Mint the URL a credentialless build uses for exactly one object.
    # `content_type` is covered by the signature, so the build must send that
    # header verbatim or the store rejects the request.
    def scratch_signed_url(key : String, method : String, content_type : String? = nil) : String
      @docs.signed_url(
        key,
        method: method,
        expires_in: SCRATCH_URL_TTL,
        content_type: content_type
      )
    end
  end
end
