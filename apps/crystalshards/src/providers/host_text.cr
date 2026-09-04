# Text taken from a repository, made storable.
#
# Postgres refuses a NUL byte in any text column: the wire protocol answers
# `invalid byte sequence for encoding "UTF8": 0x00` and rolls the statement
# back. Nothing the registry writes about a shard is exempt, because all of it
# is text a third party authored: a README, a shard.yml, a repository
# description, a topic.
#
# Measured on github.com/dogwaterdev1/rock_paper_scissor, a live repository
# with one tag, which crystalshards.org has never managed to index. Its
# README.md at v1.0.0 is 859 bytes carrying 22 NULs (a UTF-16 file committed
# with a .md name). Storing it raised PQ::PQError from inside
# `ShardIndexer#store`, which is not the `Avram::InvalidOperationError` the
# version writes rescue, so the whole transaction rolled back and the exception
# escaped the pass. The shard was left with `index_step` reading "recording",
# `index_error` NULL and no versions, and every later pass repeated it
# identically. One malformed byte, and a repository can never be read.
#
# Scrubbed here, at the boundary where a host's bytes enter the registry,
# rather than in the save operations. This is where third-party content
# arrives, so one guard covers every column it can reach and every host that
# hands us any: the operations stay about what a shard IS, not about what
# Postgres can hold.
#
# Removed rather than replaced. A NUL carries no meaning in Markdown or YAML,
# it is the residue of an encoding nobody declared, and a visible replacement
# character would put a mark in a reader's README that the author never wrote.
module HostText
  NUL = '\u0000'

  # The same object back when there is nothing to remove, which is every file
  # but a handful: this runs on every README and every shard.yml the indexer
  # fetches.
  def self.scrub(value : String) : String
    value.includes?(NUL) ? value.delete(NUL) : value
  end

  def self.scrub(value : Nil) : Nil
    nil
  end

  def self.scrub(values : Array(String)) : Array(String)
    values.map { |value| scrub(value) }
  end
end
