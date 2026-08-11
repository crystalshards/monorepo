require "../../spec_helper"

# Stored documentation is shard-authored markup, and serving it raw from this
# origin is stored XSS on crystaldocs.org. The file-serving route was removed
# outright: the only thing crystaldocs renders is the parsed docs.json,
# sanitised, inside its own pages. This spec is the tripwire. If anyone
# reinstates serving stored files, it fails loudly.
#
# The HTML files are genuinely planted in object storage for these examples.
# An assertion of the shape "the response is not this HTML" proves nothing
# when the file was never in the bucket to begin with, so an unreachable or
# unwritable store FAILS the spec instead of letting it pass vacuously.
describe "stored raw documentation files" do
  get = ->(path : String) {
    BrowserClient.exec(Lucky::RouteHelper.new(:get, path))
  }

  it "never serves a planted shard-authored HTML file, whatever its path" do
    marker = "RAW_HTML_GUARD_MUST_NEVER_BE_SERVED"
    html = %(<html><head><title>owned</title></head><body><script>alert("#{marker}")</script></body></html>)

    doc = DocFactory.create &.package_name("raw-guard").current_version("1.0.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status("success")

    storage = CrystalDocs::DocsStorageService.new
    unless storage.ensure_bucket
      fail "documentation storage is unreachable, so the raw-file guard can prove nothing"
    end

    # Every shape the removed route used to serve: the version's index, a
    # top-level file, and a nested path through the glob.
    planted = {
      "/docs/raw-guard/1.0.0/index.html"    => "index.html",
      "/docs/raw-guard/1.0.0/evil.html"     => "evil.html",
      "/docs/raw-guard/1.0.0/api/evil.html" => "api/evil.html",
    }

    planted.each_value do |file_path|
      written = storage.upload_doc_file("raw-guard", "1.0.0", file_path, html)
      unless written == html.bytesize.to_i64
        fail "could not plant #{file_path} in storage, so the raw-file guard can prove nothing"
      end
    end

    begin
      planted.each do |url, file_path|
        response = get.call(url)

        if response.status_code == 200 && response.body.includes?(marker)
          fail "#{url} returned 200 with the stored shard-authored HTML from " \
               "#{file_path}: raw file serving is back, and with it stored XSS"
        end

        response.status_code.should_not eq(200)
        response.body.should_not contain(marker)
      end
    ensure
      client = CrystalDocs::MinIOConfig.client
      planted.each_value do |file_path|
        begin
          client.delete_object(CrystalDocs::MinIOConfig.settings.docs_bucket, "raw-guard/1.0.0/#{file_path}")
        rescue
        end
      end
    end
  end
end
