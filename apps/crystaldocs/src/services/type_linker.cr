module CrystalDocs
  # Turns a type name into a link.
  #
  # Documentation is only useful if the names in it are reachable. A signature
  # mentioning `HTTP::Server::Context` should get the reader to that type,
  # whether it lives in this package, in a shard we also index, or in the
  # Crystal standard library. Resolution runs in that order, most specific
  # first.
  #
  # Anything that does not resolve stays plain text. A link that guesses is
  # worse than no link: it sends the reader to a 404 and implies the name
  # means something it does not. That is why the standard library is an
  # explicit allowlist extracted from the compiler's own source tree rather
  # than a "looks capitalised" test, which would turn every typo and every
  # unindexed dependency type into a confident link to crystal-lang.org.
  class TypeLinker
    # Top-level constants defined by the Crystal standard library, generated
    # by scanning the module, class, struct and enum declarations in the
    # compiler's src/ tree, so it reflects a real release rather than
    # recollection. Regenerate when the pinned Crystal version changes.
    STDLIB_ROOTS = Set{
      "ArgumentError", "Array", "Atomic", "Base64", "Benchmark",
      "BigDecimal", "BigFloat", "BigInt", "BigRational", "BitArray", "Bool",
      "Box", "CSV", "Channel", "Char", "Class", "Colorize", "Comparable",
      "Complex", "Compress", "Crypto", "Deprecated", "Deque", "Digest",
      "Dir", "DivisionByZeroError", "ECR", "ENV", "Enum", "Enumerable",
      "Errno", "Exception", "Experimental", "Fiber", "File", "FileUtils",
      "Flags", "Float", "Float32", "Float64", "GC", "HTML", "HTTP", "Hash",
      "INI", "IO", "IPSocket", "IndexError", "Indexable", "Int", "Int128",
      "Int16", "Int32", "Int64", "Int8", "Intrinsics",
      "InvalidBigDecimalException", "InvalidByteSequenceError", "Iterable",
      "Iterator", "JSON", "KeyError", "LLVM", "Levenshtein", "Link", "Log",
      "MIME", "Math", "NamedTuple", "Nil", "NilAssertionError",
      "NotImplementedError", "Number", "OAuth", "OAuth2", "Object",
      "OpenSSL", "OptionParser", "OverflowError", "Path", "Pointer",
      "PrettyPrint", "Proc", "Process", "Random", "Range", "Reference",
      "ReferenceStorage", "Regex", "RuntimeError", "SemanticVersion", "Set",
      "Signal", "Slice", "Socket", "Spec", "StaticArray", "Steppable",
      "String", "StringPool", "StringScanner", "Struct", "Symbol", "Sync",
      "Syscall", "System", "SystemError", "TCPServer", "TCPSocket",
      "TargetFeature", "Termios", "Thread", "Time", "Tuple", "TypeCastError",
      "UDPSocket", "UInt128", "UInt16", "UInt32", "UInt64", "UInt8",
      "UNIXServer", "UNIXSocket", "URI", "UUID", "Unicode", "Union",
      "VaList", "Value", "WaitGroup", "WasiError", "WeakRef", "WinError",
      "XML", "YAML",
    }

    # Names the compiler emits that are not types a reader can follow.
    NON_TYPES = Set{"self", "nil", "Nil", "Void", "NoReturn", "_"}

    def initialize(
      @package_name : String,
      @version : String,
      @local_types : Set(String),
      @dependency_index : Hash(String, NamedTuple(package: String, version: String)) = {} of String => NamedTuple(package: String, version: String),
      @core_api_base : String = CrystalDocs::TypeLinker.configured_core_api_base,
    )
    end

    # The standard library documentation we link to is a specific published
    # version, so it is configuration rather than a default buried in code.
    # An unset value disables core links instead of guessing at "latest",
    # which drifts and breaks links under the reader.
    def self.configured_core_api_base : String
      ENV.fetch("CRYSTAL_CORE_DOCS_URL", "")
    end

    # The set of names this package defines, so everything else is known to
    # come from somewhere else.
    def self.local_names(document : DocsDocument) : Set(String)
      names = Set(String).new
      document.all_types.each { |type| names << type.full_name }
      names
    end

    record Link, href : String, external : Bool, title : String?

    # Returns nil when the name should be rendered as plain text.
    def link_for(type_name : String) : Link?
      name = normalize(type_name)
      return nil if name.empty? || NON_TYPES.includes?(name)

      if @local_types.includes?(name)
        Link.new(
          href: "/docs/#{@package_name}/#{@version}/#{name.gsub("::", "/")}",
          external: false,
          title: nil
        )
      elsif dependency = @dependency_index[name]?
        Link.new(
          href: "/docs/#{dependency[:package]}/#{dependency[:version]}/#{name.gsub("::", "/")}",
          external: true,
          title: "#{name} in #{dependency[:package]} #{dependency[:version]}"
        )
      elsif core_link?(name)
        Link.new(
          href: "#{@core_api_base.rstrip('/')}/#{name.gsub("::", "/")}.html",
          external: true,
          title: "#{name} in the Crystal standard library"
        )
      end
    end

    # Generics, unions and nilable shorthand decorate the name; strip the
    # decoration so `Array(String)?` resolves as `Array`.
    private def normalize(type_name : String) : String
      name = type_name.strip
      name = name.split('(').first
      name = name.split('|').first.strip
      name = name.rchop('?')
      name.strip
    end

    # Only link into the standard library when it is configured AND the root
    # namespace is one the standard library actually defines.
    private def core_link?(name : String) : Bool
      return false if @core_api_base.empty?
      STDLIB_ROOTS.includes?(name.split("::").first)
    end
  end
end
