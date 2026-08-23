# Compiled at image build time so the compiler cache is populated with
# stdlib objects (JSON, HTTP). The resulting cache is copied, not shared
# writable, into each execution's scratch directory.
require "json"
require "http/client"
puts JSON.parse("[1,2,3]")
