require "json"

module CrystalDocs
  # The parsed output of `crystal docs --format=json` for one package version.
  #
  # We render documentation ourselves from this structure rather than serving
  # the HTML tree the compiler can also emit. Two reasons, and both matter:
  # the generated HTML carries its own theme and stylesheet, which cannot be
  # reconciled with ours, and it is markup written by whoever published the
  # shard, so serving it from this origin would hand shard authors script
  # execution on crystaldocs.org.
  class DocsDocument
    include JSON::Serializable

    @[JSON::Field(key: "repository_name")]
    getter repository_name : String?

    # The project README, already rendered to HTML by the compiler.
    getter body : String?

    getter program : DocType

    def self.parse(raw : String) : DocsDocument
      from_json(raw)
    end

    # Every type in the package, flattened, in the order a reader would
    # scan them. Used for the sidebar and for resolving cross links.
    def all_types : Array(DocType)
      collected = [] of DocType
      program.each_descendant { |type| collected << type }
      collected.sort_by!(&.full_name)
    end

    # Types that live directly under the root, which is what the overview
    # page lists.
    def top_level_types : Array(DocType)
      (program.types || [] of DocType).sort_by(&.full_name)
    end

    def find_type(full_name : String) : DocType?
      found : DocType? = nil
      program.each_descendant do |type|
        found = type if found.nil? && type.full_name == full_name
      end
      found
    end
  end

  # A class, module, struct, enum, alias or annotation.
  class DocType
    include JSON::Serializable

    getter html_id : String?
    getter path : String?
    getter kind : String?
    getter full_name : String
    getter name : String
    getter abstract : Bool?
    getter superclass : TypeRef?
    getter ancestors : Array(TypeRef)?
    getter doc : String?
    getter summary : String?
    getter constants : Array(DocConstant)?
    getter constructors : Array(DocMethod)?
    getter class_methods : Array(DocMethod)?
    getter instance_methods : Array(DocMethod)?
    getter macros : Array(DocMethod)?
    getter types : Array(DocType)?
    getter locations : Array(DocLocation)?

    # Yields this type and everything nested inside it, skipping the synthetic
    # root: the root is the program itself and has no documentation page.
    def each_descendant(&block : DocType ->)
      (types || [] of DocType).each do |type|
        block.call(type)
        type.each_descendant(&block)
      end
    end

    def display_kind : String
      kind || "type"
    end

    # `Kemal::Config` becomes `Kemal/Config`, which is the tail of its URL.
    def url_path : String
      full_name.gsub("::", "/")
    end

    def has_members? : Bool
      [constants, constructors, class_methods, instance_methods, macros]
        .any? { |group| group && !group.empty? }
    end

    def source_url : String?
      locations.try(&.first?).try(&.url)
    end
  end

  # A reference to a type from somewhere else in the document. Types defined
  # in this package also appear in `program`; anything that does not is
  # external, which is how cross-package and Crystal core links are decided.
  class TypeRef
    include JSON::Serializable

    getter html_id : String?
    getter kind : String?
    getter full_name : String
    getter name : String?
  end

  class DocConstant
    include JSON::Serializable

    getter name : String
    getter value : String?
    getter doc : String?
    getter summary : String?
  end

  class DocArg
    include JSON::Serializable

    getter name : String
    getter external_name : String?
    getter restriction : String?
  end

  class DocMethod
    include JSON::Serializable

    getter html_id : String?
    getter name : String
    getter abstract : Bool?
    getter args : Array(DocArg)?
    getter return_type : String?
    getter args_string : String?
    getter args_html : String?
    getter doc : String?
    getter summary : String?
    getter location : DocLocation?

    # A stable anchor for linking to one member on a type page. The compiler's
    # html_id already encodes the full signature, which is what disambiguates
    # overloads, so it is reused rather than invented.
    def anchor : String
      (html_id || name).gsub(/[^A-Za-z0-9_\-]/, "-")
    end

    def signature : String
      "#{name}#{args_string}"
    end
  end

  class DocLocation
    include JSON::Serializable

    getter filename : String?
    getter line_number : Int32?
    getter url : String?
  end
end
