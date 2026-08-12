# An object store that holds a set of keys and nothing else.
#
# The reconciliation's whole question is which keys the docs bucket holds, so a
# fake that answers exactly that, and can also refuse to answer, covers every
# decision it makes. It is a real `CrystalStorage::ObjectStore` rather than a
# narrower module so the code under test reaches it through the interface
# production uses, and so a new abstract method cannot be added to that
# interface without this failing to compile.
class FakeObjectStore < CrystalStorage::ObjectStore
  # When set, every operation reports the store could not answer, which is a
  # different fact from an empty bucket and has to stay different: collapsing
  # them is what would let a storage outage read as "nothing has been built".
  property unavailable : Bool

  getter objects : Hash(String, Bytes)

  def initialize(keys : Enumerable(String) = [] of String, @unavailable : Bool = false)
    super("fake-docs")
    @objects = {} of String => Bytes
    keys.each { |key| @objects[key] = Bytes.empty }
  end

  def get(key : String) : Bytes?
    refuse("read", key)
    @objects[key]?
  end

  def put(key : String, body : Bytes, content_type : String) : Nil
    refuse("write", key)
    @objects[key] = body
  end

  def delete(key : String) : Nil
    refuse("delete", key)
    @objects.delete(key)
  end

  # Sorted, because the real listing arrives in lexical order and a spec that
  # happened to depend on insertion order would pass here and not there.
  def list(prefix : String) : Array(String)
    refuse("list", prefix)
    @objects.keys.select(&.starts_with?(prefix)).sort!
  end

  def exists?(key : String) : Bool
    refuse("stat", key)
    @objects.has_key?(key)
  end

  def ensure_bucket : Bool
    !unavailable
  end

  def signed_url(
    key : String,
    method : String = "GET",
    expires_in : Time::Span = 15.minutes,
    content_type : String? = nil,
  ) : String
    "https://signed.invalid/#{bucket}/#{key}?method=#{normalized(method)}"
  end

  private def refuse(operation : String, key : String) : Nil
    return unless unavailable

    raise CrystalStorage::Unavailable.new(operation, key, "the fake store was told to be unreachable")
  end
end
