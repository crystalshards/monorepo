You need an HTTP client. You search, you turn up three, and you have no way to tell which one still compiles against the Crystal you are running.

That has been the shape of Crystal discovery since the language shipped. The problem was never that nobody built a catalogue. Several people did, and the ones still running are doing real work this ecosystem is better for. The problem is what a catalogue is allowed to contain. If a shard has to be submitted before it appears, the list is a record of who remembered to submit, not of what exists.

The original CrystalShards took the other route. It crawled the git hosts looking for the file that makes a repository a shard, a `shard.yml` at the root, and indexed what it found whether or not the author had ever heard of us. We ran that site until 2022.

It is back, and it crawls again. GitHub caps any single search at a thousand results, so the sweep partitions the search by manifest size and keeps splitting until every window fits under that cap. That is what makes it exhaustive instead of a thousand result sample. Right now it holds a little over five thousand shards. GitLab and Codeberg are wired and waiting on credentials.

What is new is that it does not stand alone. A shard page links to its documentation on CrystalDocs, which builds docs for the same versions this site indexes. It shows you what depends on it, drawn from the dependency graph across every shard we hold rather than only the ones that thought to mention each other. Visiting a shard nobody has indexed yet commissions the index while you wait, so a cold page fills itself in instead of telling you to come back later.

If a shard of yours is missing, it means we have not reached it yet, or your host is not crawled yet. Both of those are our problem, not yours.
