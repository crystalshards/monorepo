# The Crystal repository is not a shard on this site, however it is indexed.
#
# The crawler finds github.com/crystal-lang/crystal, because it has a shard.yml
# like anything else, and the registry records it. Followed down the ordinary
# path it produces a page that can never work: documenting the standard library
# needs its own entrypoint, its own CRYSTAL_PATH and a toolchain the shard
# sandbox deliberately does not carry, so every attempt fails and the page a
# reader lands on says the build failed. That was the state of the most
# important package on the site.
#
# It is also a second identity for something we already publish. The standard
# library is `CORE_PACKAGE`, a bare key, and that key is what the storage
# layout, the type linker and every core cross link already use. Two URLs for
# one library means two build states to keep in step and two answers to "where
# do I read String".
#
# So the repository URLs redirect to the library. 301, because this is a
# permanent statement about identity rather than a routing convenience, and the
# redirect carries the version and the type path so a link into a specific page
# lands on the same page rather than the front of the library.
module Docs::CoreRepository
  # Matched as a constant, never against registry data. Selecting behaviour
  # from a row an attacker can publish would let anyone claim to be the
  # standard library; the same reasoning pins the clone URL in the build path.
  CORE_REPOSITORY = "github.com/crystal-lang/crystal"

  private def core_repository?(slug : String) : Bool
    slug == CORE_REPOSITORY
  end
end
