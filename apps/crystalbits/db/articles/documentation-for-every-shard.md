Go has pkg.go.dev. Rust has docs.rs. Crystal has whatever each library author remembered to publish, wherever they decided to put it.

That is not a knock on anyone. `crystal docs` is a good tool and it ships in the box. The gap is publishing. Generating documentation is one command; hosting it, keeping it current, and doing that for every version anyone still depends on is a standing chore that lands on the author. Plenty of excellent shards have no published docs at all, and plenty more have docs for one version from three years ago.

CrystalDocs builds them instead. Point at a shard and a version and it compiles the documentation itself, then serves it. The first person to ask for a version nobody has built yet is the one who starts that build, just by asking.

Two things fall out of doing this centrally that an author publishing their own site cannot do.

The first is linking across projects. When a method signature mentions `DB::Connection`, that type is a link to crystal-db's own page, at the version the shard you are reading actually resolved to. Not the newest one. The one it pinned.

The second is the standard library. We host it here, built from the compiler's own repository at the commit its tag points at, so `String` in a signature links to `String`. Following a type out of a shard you have never seen, into the standard library, and back again is one click each way.

One deliberate cost, because it shapes what you see. We render pages from the compiler's machine readable output rather than serving the HTML tree it can also emit. That tree carries its own theme, and more to the point it is markup written by whoever published the shard. Serving it from this origin would hand every shard author script execution on this domain. So doc comments and READMEs are treated as untrusted input, put through an allowlist, and rendered into our own pages.
