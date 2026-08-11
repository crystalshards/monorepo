module CrystalDocs
  # Reads built documentation out of the docs bucket.
  #
  # Everything here goes through `CrystalStorage.docs`, the object store
  # interface: Google Cloud Storage in production, the local store in
  # development. This service knows about documentation, not about a backend.
  class DocsStorageService
    # Outcome of a documentation fetch.
    #
    # "the store says this file does not exist" and "the store never gave us
    # an answer" are different facts. Collapsing both into a bare nil meant a
    # storage outage looked identical to missing documentation, so callers keep
    # the distinction and only tell a reader the docs are gone when they are.
    struct Fetch
      getter content : String?

      def self.found(content : String) : Fetch
        new(content, store_answered: true)
      end

      # The store answered, and the file is not in the bucket.
      def self.absent : Fetch
        new(nil, store_answered: true)
      end

      # The store could not be reached, or failed for some reason other than a
      # missing object, so whether the documentation exists is unknown.
      def self.unavailable : Fetch
        new(nil, store_answered: false)
      end

      def initialize(@content : String?, @store_answered : Bool)
      end

      def found? : Bool
        !@content.nil?
      end

      # True when "no content" is the store's own answer rather than our guess.
      def store_answered? : Bool
        @store_answered
      end
    end

    def initialize(@store : CrystalStorage::ObjectStore = CrystalStorage.docs)
    end

    # Download a documentation file.
    def fetch_doc_file(package_name : String, version : String, file_path : String) : Fetch
      key = docs_key(package_name, version, file_path)

      begin
        if content = @store.get_string(key)
          Fetch.found(content)
        else
          Fetch.absent
        end
      rescue ex : CrystalStorage::Unavailable
        log_unavailable(key, ex)
        Fetch.unavailable
      end
    end

    # List all files in a documentation version. Empty when the store is
    # unreachable, so treat it as "nothing we can show" rather than proof
    # that a version has no files.
    def list_doc_files(package_name : String, version : String) : Array(String)
      prefix = "#{package_name}/#{version}/"

      begin
        @store.list(prefix).map(&.sub(prefix, ""))
      rescue ex : CrystalStorage::Unavailable
        log_unavailable(prefix, ex)
        [] of String
      end
    end

    # There is deliberately no `fetch_index` or `docs_exist?` keyed on an
    # index.html. A version's one artifact is docs.json, which `DocsLoader`
    # fetches directly; nothing writes HTML, so those only ever answered "no".

    # Report whether the docs bucket is reachable and usable. In production the
    # bucket is terraform's; locally this creates it on demand.
    def ensure_bucket : Bool
      @store.ensure_bucket
    end

    # Store a documentation file. Returns the number of bytes written, or nil
    # when the store could not be reached, so callers can report honestly
    # instead of assuming the write landed.
    def upload_doc_file(package_name : String, version : String, file_path : String, content : String) : Int64?
      key = docs_key(package_name, version, file_path)

      begin
        @store.put(key, content, content_type_for(file_path))
        content.bytesize.to_i64
      rescue ex : CrystalStorage::Unavailable
        log_unavailable(key, ex)
        nil
      end
    end

    # Remove a stored documentation file. Used by specs that plant artifacts.
    def delete_doc_file(package_name : String, version : String, file_path : String) : Nil
      @store.delete(docs_key(package_name, version, file_path))
    rescue ex : CrystalStorage::Unavailable
      log_unavailable(docs_key(package_name, version, file_path), ex)
    end

    private def content_type_for(file_path : String) : String
      case File.extname(file_path)
      when ".html" then "text/html"
      when ".css"  then "text/css"
      when ".js"   then "application/javascript"
      when ".json" then "application/json"
      else              "application/octet-stream"
      end
    end

    private def docs_key(package_name : String, version : String, file_path : String) : String
      "#{package_name}/#{version}/#{file_path}"
    end

    private def log_unavailable(key : String, error : Exception) : Nil
      Lucky::Log.dexter.warn do
        {docs_storage_unavailable: key, error: error.message}
      end
    end
  end
end
