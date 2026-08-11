# Two real drafts written from real Reddit threads.
#
# These were drafted by hand from material gathered off r/crystal_programming
# rather than by the runtime generator, which needs a model API key this repo
# does not carry. They go in through exactly the same path as a generated
# draft: ContentIngestor, DRAFT state, machine_drafted true, sources attached.
# They are labelled machine-drafted because that is what they are, and neither
# is public until an editor approves it.
#
# The prose is original. Nothing from the threads is reproduced; each item
# links to the discussions it was written from.
class Bits::SeedRedditDrafts < LuckyTask::Task
  summary "Seed two machine-drafted news items written from real Reddit discussion"

  help_message <<-TEXT
    Adds two drafts to the review queue, written from public threads on
    r/crystal_programming. Both land as DRAFT, marked machine-drafted, with
    their source URLs attached.

    Re-running does not duplicate: items are deduplicated on their source URL.
    TEXT

  GCRY_PRIMARY   = "https://www.reddit.com/r/crystal_programming/comments/1v9pg4y/gcry_a_garbage_collector_written_in_pure_crystal/"
  GCRY_FASTER    = "https://www.reddit.com/r/crystal_programming/comments/1vf7576/next_version_of_gcry_is_faster_than_boehm_gc_and/"
  GCRY_SPONSORS  = "https://www.reddit.com/r/crystal_programming/comments/1vbpf5v/i_cant_find_a_job_so_im_building_crystals_future/"
  RELEASE_THREAD = "https://www.reddit.com/r/crystal_programming/comments/1uyd8un/crystal_1210_is_out_and_execution_contexts_are_on/"
  RELEASE_POST   = "https://crystal-lang.org/2026/07/16/1.21.0-released/"

  LICENSE_NOTE = "Original text written for CrystalBits from the public discussions " \
                 "listed above, which are linked rather than reproduced. Drafted during " \
                 "development rather than by the runtime generator, and held for " \
                 "editorial review like everything else."

  def call
    seed_gcry
    seed_execution_contexts
    puts "Seeded drafts are in the review queue at /admin/moderation. None are public."
  end

  private def seed_gcry
    store(
      source_url: GCRY_PRIMARY,
      title: "A garbage collector for Crystal, written in Crystal",
      summary: "gcry replaces Boehm with a collector written as an ordinary Crystal shard, " \
               "and its numbers have moved from roughly 89 percent of Boehm's throughput to parity.",
      published_at: Time.utc(2026, 8, 4),
      sources: [GCRY_PRIMARY, GCRY_FASTER, GCRY_SPONSORS],
      body: <<-MARKDOWN
        Crystal has always leaned on Boehm for garbage collection: a C library, conservative,
        and effectively opaque to anyone working in Crystal itself. [gcry](https://github.com/sdogruyol/gcry)
        is an attempt to change that. It is a conservative mark and sweep collector written in
        Crystal, shipped as an ordinary shard, and switched on by building with `-Dgc_none` and
        requiring it. No compiler fork, no C.

        When [version 0.14.0 was announced](#{GCRY_PRIMARY}), the pitch was mostly about being
        able to read the thing. Boehm is a foreign library you link against; gcry is Crystal
        source you can step through in a debugger and change. The figures at that point put it
        near 89 percent of Boehm's throughput on a Kemal workload under Linux, with noticeably
        smaller resident memory.

        A week later the author [reported parity](#{GCRY_FASTER}): marginally ahead of Boehm on
        throughput and around 8 percent lighter on memory, measured against a Kemal application
        actually in production.

        The replies are worth reading for the constraint they surface. Asked why not adopt MMTk
        rather than build another collector, a Crystal core member pointed out that Crystal
        needs its objects to stay where they are, and most of MMTk's collectors relocate them.
        That closes off the obvious shortcut.

        Also aired in that thread: a challenge about how much of the code was AI-written, and
        the author's reply that he uses AI as a tool while the architecture and the benchmarking
        are his. Worth knowing whichever way you weigh it.

        The work is being [funded through GitHub Sponsors](#{GCRY_SPONSORS}) while its author is
        between jobs.
        MARKDOWN
    )
  end

  private def seed_execution_contexts
    store(
      source_url: RELEASE_THREAD,
      title: "Crystal 1.21.0 turns execution contexts on by default",
      summary: "The multithreading runtime is no longer opt-in. Most code will not notice, but " \
               "fibers are no longer pinned to a thread, and that part is a real breaking change.",
      published_at: Time.utc(2026, 7, 16),
      sources: [RELEASE_THREAD, RELEASE_POST],
      body: <<-MARKDOWN
        [Crystal 1.21.0](#{RELEASE_POST}) arrived with 161 changes from 21 contributors, and one
        of them matters more than the rest: execution contexts, the multithreading design from
        RFC 0002, are now the default runtime rather than something you opt into with a flag.

        Day to day this is quiet. The default context still runs at a parallelism of one, so a
        program that never asks for more threads behaves as it always did. You opt into real
        parallelism by resizing that context or by creating another.

        The part worth checking is thread pinning, or rather its absence. A fiber can now resume
        on a different thread after it yields, and inside a parallel context it can move threads
        across a blocking syscall. Any code keeping state in thread locals and assuming it
        survives a yield needs a read. Relatedly, `spawn(same_thread: true)` no longer works: it
        is deprecated in general and raises in a parallel context.

        A [community write-up on r/crystal_programming](#{RELEASE_THREAD}) picked out the smaller
        changes worth knowing. `%W` gives you a word array that does support interpolation and
        escape sequences, which `%w` does not. `Channel(T)` now implements `Iterator(T)`.
        `String#present?` exists. There are `UUID.v6` and `UUID.v8` generators, and an
        experimental `Socket#sendfile`.

        Two more breaking changes to note. The automatic fallback to the original PCRE is gone,
        so anything still relying on it needs `-Duse_pcre`. And `case ... when Bar, Baz` now
        tests each type on its own rather than treating the list as a union; write
        `when Bar | Baz` if the union was what you wanted.
        MARKDOWN
    )
  end

  private def store(
    source_url : String,
    title : String,
    summary : String,
    body : String,
    published_at : Time,
    sources : Array(String),
  )
    _, change = ContentIngestor.upsert(
      source_url: source_url,
      origin: ContentItem::Origin::GENERATED,
      title: title,
      summary: summary,
      body: body,
      attribution: DraftGenerator::ATTRIBUTION,
      original_author: "CrystalBits (machine-drafted)",
      original_published_at: published_at,
      license_note: LICENSE_NOTE,
      machine_drafted: true,
      source_urls: sources,
    )

    puts "  #{change.to_s.downcase}: #{title}"
    sources.each { |url| puts "      source: #{url}" }
  end
end
