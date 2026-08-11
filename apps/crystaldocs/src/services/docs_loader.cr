module CrystalDocs
  # Fetches and parses a package version's docs.json.
  #
  # Parsing is not free (kemal's document is around 200K), so results are held
  # briefly in memory. Documentation for a published version never changes, so
  # the only staleness risk is a rebuild of the same version, which is rare and
  # self-corrects when the entry expires.
  class DocsLoader
    record Result, document : DocsDocument?, store_answered : Bool do
      def store_answered? : Bool
        store_answered
      end
    end

    record Entry, document : DocsDocument, fetched_at : Time

    CACHE_TTL = 5.minutes

    @@cache = {} of String => Entry
    @@mutex = Mutex.new

    # Test seam, mirroring the pattern the rest of the services use.
    class_property loader : Proc(DocsLoader)? = nil

    def self.build : DocsLoader
      if custom = @@loader
        custom.call
      else
        new
      end
    end

    def self.clear_cache
      @@mutex.synchronize { @@cache.clear }
    end

    def initialize(@storage : DocsStorageService = DocsStorageService.new)
    end

    def load(package_name : String, version : String) : Result
      key = "#{package_name}/#{version}"

      if cached = read_cache(key)
        return Result.new(document: cached, store_answered: true)
      end

      fetch = @storage.fetch_doc_file(
        package_name: package_name,
        version: version,
        file_path: "docs.json"
      )

      raw = fetch.content
      return Result.new(document: nil, store_answered: fetch.store_answered?) unless raw

      document = DocsDocument.parse(raw)
      write_cache(key, document)
      Result.new(document: document, store_answered: true)
    rescue ex : JSON::Error
      # Storage answered, so the version is published; the artifact is simply
      # not usable. Saying so beats rendering an empty page that implies the
      # package has no API.
      Log.error { "Unparseable docs.json for #{package_name} #{version}: #{ex.message}" }
      Result.new(document: nil, store_answered: true)
    end

    private def read_cache(key : String) : DocsDocument?
      @@mutex.synchronize do
        entry = @@cache[key]?
        next nil unless entry

        if Time.utc - entry.fetched_at > CACHE_TTL
          @@cache.delete(key)
          nil
        else
          entry.document
        end
      end
    end

    private def write_cache(key : String, document : DocsDocument)
      @@mutex.synchronize { @@cache[key] = Entry.new(document, Time.utc) }
    end
  end
end
