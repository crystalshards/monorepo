require "awscr-s3"
require "base64"
require "http/client"
require "json"
require "openssl"
require "uri"

# One object store, two backends.
#
# Production is Google Cloud Storage reached with the Cloud Run service's own
# identity: a token from the metadata server for the data plane, and IAM
# SignBlob for V4 URL signing. There is no key file and no static credential
# anywhere in this path.
#
# Development is the S3-compatible store docker-compose already runs. It is
# the development implementation of this interface and nothing else; no
# production code path selects it, names it, or reads its variables directly.
#
# Signed URLs are not a convenience here. The documentation build runs
# untrusted third-party shard code and therefore holds no credentials at all,
# so a signed GET in and a signed PUT out is the entire mechanism by which it
# receives input and returns output. Development uses a real object store
# rather than the filesystem precisely so that mechanism is exercised outside
# production instead of only there.
#
# This file is intentionally identical in every app that stores objects. The
# apps build as independent images with `apps/<app>` as the docker context, so
# nothing outside an app directory reaches its image and there is no shared
# shard to hold this. Keeping the copies byte-identical makes a later
# extraction a move rather than a merge, and makes drift a one-line `cmp`.
module CrystalStorage
  # The store could not answer. Distinct from "the store answered, and the
  # object is not there", which is a nil return. Callers that report storage
  # health to a reader depend on telling those apart: collapsing them makes an
  # outage look exactly like missing documentation.
  class Unavailable < Exception
    def initialize(operation : String, key : String, cause : String)
      super("object store could not #{operation} #{key.inspect}: #{cause}")
    end
  end

  # A bucket name is a deployment fact. Defaulting one in production is how a
  # pipeline appears to work while writing nothing anybody will ever read, so
  # production refuses to boot instead.
  class MissingBucket < Exception
    def initialize(variable : String, holds : String)
      super(<<-MESSAGE)
      #{variable} is not set.

      It names the bucket holding #{holds}, and production will not start
      without it. An object store with no bucket name does not fail at the
      point of use in any visible way: writes go nowhere and reads come back
      empty, which is indistinguishable from a package that simply has no
      documentation yet.

      Set it to the bucket for this environment, for example:

        #{variable}=crystalshards-docs

      In development and test it defaults to the bucket `make services`
      creates locally.
      MESSAGE
    end
  end

  # Object keys, in one place, because two services agree on them across a
  # process boundary. CrystalShards writes what CrystalDocs reads, and the
  # documentation build launcher signs URLs for keys it never opens itself, so
  # a key built by hand in any one of those three drifts silently.
  module Keys
    # The published package tarball. This is the artifact a user downloads.
    def self.package(shard_name : String, version : String) : String
      "#{shard_name}/#{version}/#{shard_name}-#{version}.tar.gz"
    end

    # The published documentation artifact: exactly one `crystal docs
    # --format=json` document per version. No generated HTML is ever stored,
    # because shard-authored markup served from our origin is stored XSS.
    def self.docs_json(shard_name : String, version : String) : String
      "#{shard_name}/#{version}/docs.json"
    end
  end

  # Bucket names, resolved once, failing closed in production.
  module Buckets
    DOCS_ENV     = "DOCS_BUCKET"
    PACKAGES_ENV = "PACKAGES_BUCKET"

    # What `make services` creates locally. Development only.
    DEV_DOCS     = "crystal-docs"
    DEV_PACKAGES = "packages"

    def self.docs : String
      resolve(DOCS_ENV, DEV_DOCS, "built documentation")
    end

    def self.packages : String
      resolve(PACKAGES_ENV, DEV_PACKAGES, "published package tarballs")
    end

    # Force resolution of the buckets an app actually uses, so a missing name
    # is a startup failure naming the variable rather than a runtime surprise
    # on the first upload. Which buckets those are is per-app policy and lives
    # in each app's own config, because a service with no role on a bucket is
    # never told that bucket's name and must not demand it.
    def self.require!(*names : Symbol) : Nil
      names.each do |name|
        case name
        when :docs     then docs
        when :packages then packages
        else                raise ArgumentError.new("unknown bucket #{name}")
        end
      end
    end

    private def self.resolve(variable : String, development_default : String, holds : String) : String
      raw = ENV[variable]?

      if raw.nil? || raw.blank?
        raise MissingBucket.new(variable, holds) if LuckyEnv.production?
        return development_default
      end

      raw
    end
  end

  # get, put and signed_url are the contract. The rest are the operations the
  # existing call sites genuinely need; they are here rather than on a backend
  # so no caller ever reaches past the interface to a client.
  abstract class ObjectStore
    getter bucket : String

    def initialize(@bucket : String)
    end

    # nil means the store answered and the object is not there. Raises
    # `Unavailable` when the store could not answer at all.
    abstract def get(key : String) : Bytes?
    abstract def put(key : String, body : Bytes, content_type : String) : Nil
    abstract def delete(key : String) : Nil
    abstract def list(prefix : String) : Array(String)
    abstract def exists?(key : String) : Bool

    # A URL carrying its own authorization, for a caller that has none.
    # `method` is "GET" or "PUT". When `content_type` is given it is covered by
    # the signature, so the caller must send exactly that header or the store
    # rejects the request.
    abstract def signed_url(
      key : String,
      method : String = "GET",
      expires_in : Time::Span = 15.minutes,
      content_type : String? = nil,
    ) : String

    # Create the bucket if it is missing. In production the bucket is
    # terraform's, so this only reports whether it is reachable.
    abstract def ensure_bucket : Bool

    def put(key : String, body : String, content_type : String) : Nil
      put(key, body.to_slice, content_type)
    end

    def get_string(key : String) : String?
      bytes = get(key)
      bytes ? String.new(bytes) : nil
    end

    def delete_prefix(prefix : String) : Nil
      list(prefix).each { |key| delete(key) }
    end

    protected def normalized(method : String) : String
      upcased = method.upcase
      return upcased if upcased == "GET" || upcased == "PUT"
      raise ArgumentError.new("signed_url supports GET and PUT, not #{method.inspect}")
    end
  end

  # Google Cloud Storage using the running service's own identity.
  class GCS < ObjectStore
    API_HOST      = "storage.googleapis.com"
    IAM_HOST      = "iamcredentials.googleapis.com"
    METADATA_HOST = "metadata.google.internal"

    # The token and the service account email belong to the process, not to a
    # bucket, so they are cached once for every store in it.
    @@identity_mutex = Mutex.new
    @@access_token : String?
    @@token_expires_at : Time = Time.unix(0)
    @@service_account_email : String?

    def get(key : String) : Bytes?
      response = api_get("/storage/v1/b/#{escape(bucket)}/o/#{escape(key)}?alt=media")
      return nil if response.status_code == 404
      unless response.status_code == 200
        raise Unavailable.new("read", key, "HTTP #{response.status_code}")
      end
      response.body.to_slice
    rescue ex : IO::Error | Socket::Error
      raise Unavailable.new("read", key, ex.message || ex.class.name)
    end

    def put(key : String, body : Bytes, content_type : String) : Nil
      path = "/upload/storage/v1/b/#{escape(bucket)}/o?uploadType=media&name=#{escape(key)}"
      headers = authorized_headers
      headers["Content-Type"] = content_type

      response = HTTP::Client.post("https://#{API_HOST}#{path}", headers: headers, body: body)
      unless response.success?
        raise Unavailable.new("write", key, "HTTP #{response.status_code}")
      end
    rescue ex : IO::Error | Socket::Error
      raise Unavailable.new("write", key, ex.message || ex.class.name)
    end

    def delete(key : String) : Nil
      response = HTTP::Client.delete(
        "https://#{API_HOST}/storage/v1/b/#{escape(bucket)}/o/#{escape(key)}",
        headers: authorized_headers
      )
      # A delete of something already gone is the state the caller wanted.
      return if response.status_code == 404
      unless response.success?
        raise Unavailable.new("delete", key, "HTTP #{response.status_code}")
      end
    rescue ex : IO::Error | Socket::Error
      raise Unavailable.new("delete", key, ex.message || ex.class.name)
    end

    def list(prefix : String) : Array(String)
      keys = [] of String
      page_token : String? = nil

      loop do
        path = String.build do |io|
          io << "/storage/v1/b/" << escape(bucket) << "/o?prefix=" << escape(prefix)
          io << "&pageToken=" << escape(page_token) if page_token
        end

        response = api_get(path)
        unless response.status_code == 200
          raise Unavailable.new("list", prefix, "HTTP #{response.status_code}")
        end

        parsed = JSON.parse(response.body)
        parsed["items"]?.try &.as_a.each { |item| keys << item["name"].as_s }

        page_token = parsed["nextPageToken"]?.try &.as_s
        break unless page_token
      end

      keys
    rescue ex : IO::Error | Socket::Error
      raise Unavailable.new("list", prefix, ex.message || ex.class.name)
    end

    def exists?(key : String) : Bool
      response = api_get("/storage/v1/b/#{escape(bucket)}/o/#{escape(key)}")
      return false if response.status_code == 404
      return true if response.status_code == 200
      raise Unavailable.new("stat", key, "HTTP #{response.status_code}")
    rescue ex : IO::Error | Socket::Error
      raise Unavailable.new("stat", key, ex.message || ex.class.name)
    end

    # Terraform owns the bucket in production. Reporting reachability is the
    # only honest thing this can do, and it is what callers actually ask.
    def ensure_bucket : Bool
      response = api_get("/storage/v1/b/#{escape(bucket)}")
      response.status_code == 200
    rescue IO::Error | Socket::Error | Unavailable
      false
    end

    # V4 signing. The private key never leaves Google: the string to sign goes
    # to IAM SignBlob and comes back signed, which is what lets this run on a
    # service account with no downloaded key.
    def signed_url(
      key : String,
      method : String = "GET",
      expires_in : Time::Span = 15.minutes,
      content_type : String? = nil,
    ) : String
      verb = normalized(method)
      now = Time.utc
      datestamp = now.to_s("%Y%m%d")
      timestamp = now.to_s("%Y%m%dT%H%M%SZ")
      scope = "#{datestamp}/auto/storage/goog4_request"
      credential = "#{self.class.service_account_email}/#{scope}"

      headers = {"host" => API_HOST}
      headers["content-type"] = content_type if content_type
      signed_headers = headers.keys.sort!
      canonical_headers = signed_headers.map { |name| "#{name}:#{headers[name]}\n" }.join
      signed_header_list = signed_headers.join(";")

      # Already in sorted order, which is what the canonical form requires.
      canonical_query = [
        {"X-Goog-Algorithm", "GOOG4-RSA-SHA256"},
        {"X-Goog-Credential", credential},
        {"X-Goog-Date", timestamp},
        {"X-Goog-Expires", expires_in.total_seconds.to_i.to_s},
        {"X-Goog-SignedHeaders", signed_header_list},
      ].map { |(name, value)| "#{escape(name)}=#{escape(value)}" }.join("&")

      canonical_resource = "/#{bucket}/#{key.split('/').map { |part| escape(part) }.join('/')}"

      canonical_request = [
        verb,
        canonical_resource,
        canonical_query,
        canonical_headers,
        signed_header_list,
        "UNSIGNED-PAYLOAD",
      ].join("\n")

      string_to_sign = [
        "GOOG4-RSA-SHA256",
        timestamp,
        scope,
        OpenSSL::Digest.new("SHA256").update(canonical_request).final.hexstring,
      ].join("\n")

      signature = self.class.sign_blob(string_to_sign)

      "https://#{API_HOST}#{canonical_resource}?#{canonical_query}&X-Goog-Signature=#{signature}"
    end

    private def api_get(path : String) : HTTP::Client::Response
      HTTP::Client.get("https://#{API_HOST}#{path}", headers: authorized_headers)
    end

    private def authorized_headers : HTTP::Headers
      HTTP::Headers{"Authorization" => "Bearer #{self.class.access_token}"}
    end

    private def escape(value : String) : String
      URI.encode_path_segment(value)
    end

    # Signs with the running identity's own key, held by Google. Requires
    # roles/iam.serviceAccountTokenCreator on itself; without it this is the
    # 403 that explains itself.
    def self.sign_blob(payload : String) : String
      email = service_account_email
      response = HTTP::Client.post(
        "https://#{IAM_HOST}/v1/projects/-/serviceAccounts/#{URI.encode_path_segment(email)}:signBlob",
        headers: HTTP::Headers{
          "Authorization" => "Bearer #{access_token}",
          "Content-Type"  => "application/json",
        },
        body: {payload: Base64.strict_encode(payload)}.to_json
      )

      unless response.success?
        raise Unavailable.new("sign a URL for", email, "IAM SignBlob returned HTTP #{response.status_code}")
      end

      Base64.decode(JSON.parse(response.body)["signedBlob"].as_s).hexstring
    end

    def self.access_token : String
      @@identity_mutex.synchronize do
        cached = @@access_token
        return cached if cached && Time.utc < @@token_expires_at

        response = metadata_get("/computeMetadata/v1/instance/service-accounts/default/token")
        parsed = JSON.parse(response)
        token = parsed["access_token"].as_s

        # Renew a minute early rather than discover expiry mid-request.
        @@token_expires_at = Time.utc + (parsed["expires_in"].as_i - 60).seconds
        @@access_token = token
        token
      end
    end

    def self.service_account_email : String
      @@identity_mutex.synchronize do
        cached = @@service_account_email
        next cached if cached

        email = metadata_get("/computeMetadata/v1/instance/service-accounts/default/email").strip
        @@service_account_email = email
        email
      end
    end

    private def self.metadata_get(path : String) : String
      response = HTTP::Client.get(
        "http://#{METADATA_HOST}#{path}",
        headers: HTTP::Headers{"Metadata-Flavor" => "Google"}
      )

      unless response.success?
        raise Unavailable.new("reach", METADATA_HOST, "HTTP #{response.status_code}")
      end

      response.body
    rescue ex : IO::Error | Socket::Error
      raise Unavailable.new("reach", METADATA_HOST, ex.message || ex.class.name)
    end
  end

  # The development backend: the S3-compatible object store docker-compose
  # runs. Selected only outside production, so nothing in a production code
  # path reaches this class.
  class Local < ObjectStore
    ENDPOINT_ENV   = "STORAGE_ENDPOINT"
    ACCESS_KEY_ENV = "STORAGE_ACCESS_KEY"
    SECRET_KEY_ENV = "STORAGE_SECRET_KEY"
    REGION_ENV     = "STORAGE_REGION"

    DEFAULT_ENDPOINT = "http://localhost:9000"
    DEFAULT_REGION   = "us-east-1"

    def initialize(bucket : String)
      super(bucket)
      @endpoint = ENV[ENDPOINT_ENV]?.presence || DEFAULT_ENDPOINT
      @region = ENV[REGION_ENV]?.presence || DEFAULT_REGION
      # Local-only credentials for a local-only container. Production never
      # reaches this class, so there is no production default being invented.
      @access_key = ENV[ACCESS_KEY_ENV]?.presence || "minioadmin"
      @secret_key = ENV[SECRET_KEY_ENV]?.presence || "minioadmin"
    end

    def get(key : String) : Bytes?
      client.get_object(bucket, key).body.to_slice
    rescue Awscr::S3::NoSuchKey
      nil
    rescue ex : Awscr::S3::Exception | IO::Error
      # A missing key surfaces as a generic 404 rather than NoSuchKey on some
      # S3 implementations, so treat that shape as an answer too.
      return nil if not_found?(ex)
      raise Unavailable.new("read", key, ex.message || ex.class.name)
    end

    def put(key : String, body : Bytes, content_type : String) : Nil
      client.put_object(bucket, key, body, {"Content-Type" => content_type})
    rescue ex : Awscr::S3::Exception | IO::Error
      raise Unavailable.new("write", key, ex.message || ex.class.name)
    end

    def delete(key : String) : Nil
      client.delete_object(bucket, key)
    rescue ex : Awscr::S3::Exception | IO::Error
      return if not_found?(ex)
      raise Unavailable.new("delete", key, ex.message || ex.class.name)
    end

    def list(prefix : String) : Array(String)
      keys = [] of String
      client.list_objects(bucket, prefix: prefix).each do |page|
        page.contents.each { |object| keys << object.key }
      end
      keys
    rescue ex : Awscr::S3::Exception | IO::Error
      raise Unavailable.new("list", prefix, ex.message || ex.class.name)
    end

    def exists?(key : String) : Bool
      client.head_object(bucket, key)
      true
    rescue Awscr::S3::NoSuchKey
      false
    rescue ex : Awscr::S3::Exception | IO::Error
      return false if not_found?(ex)
      raise Unavailable.new("stat", key, ex.message || ex.class.name)
    end

    def ensure_bucket : Bool
      client.put_bucket(bucket)
      true
    rescue Awscr::S3::BucketAlreadyExists | Awscr::S3::BucketAlreadyOwnedByYou
      true
    rescue Awscr::S3::Exception | IO::Error
      false
    end

    def signed_url(
      key : String,
      method : String = "GET",
      expires_in : Time::Span = 15.minutes,
      content_type : String? = nil,
    ) : String
      verb = normalized(method)

      options = Awscr::S3::Presigned::Url::Options.new(
        aws_access_key: @access_key,
        aws_secret_key: @secret_key,
        region: @region,
        object: key,
        bucket: bucket,
        # Carries scheme, host and port, so the URL points at the local store
        # rather than at Amazon. `include_port` stays false: the endpoint has
        # already put the port in the host, and asking for it again appends it
        # twice.
        endpoint: @endpoint,
        expires: expires_in.total_seconds.to_i,
        force_path_style: true
      )

      Awscr::S3::Presigned::Url.new(options).for(verb == "PUT" ? :put : :get)
    end

    private def client : Awscr::S3::Client
      Awscr::S3::Client.new(
        region: @region,
        aws_access_key: @access_key,
        aws_secret_key: @secret_key,
        endpoint: @endpoint
      )
    end

    private def not_found?(error : Exception) : Bool
      !!error.message.try(&.includes?("404"))
    end
  end

  @@mutex = Mutex.new
  @@docs : ObjectStore?
  @@packages : ObjectStore?

  # Test seams. Setting either swaps the store everything reads, so a spec can
  # run with no object store at all.
  def self.docs=(store : ObjectStore?)
    @@mutex.synchronize { @@docs = store }
  end

  def self.packages=(store : ObjectStore?)
    @@mutex.synchronize { @@packages = store }
  end

  # Built on first touch, never at require time. A spec that never stores an
  # object must not fail because storage is unconfigured.
  def self.docs : ObjectStore
    @@mutex.synchronize { @@docs ||= build(Buckets.docs) }
  end

  def self.packages : ObjectStore
    @@mutex.synchronize { @@packages ||= build(Buckets.packages) }
  end

  def self.build(bucket : String) : ObjectStore
    LuckyEnv.production? ? GCS.new(bucket) : Local.new(bucket)
  end
end
