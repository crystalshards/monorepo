#!/usr/bin/env crystal
require "json"

unless JSON.parse(STDIN.gets_to_end)["prompt"]?.try(&.as_s?.try(&.=~(/^\[main\]/)))
  puts {{ read_file("#{__DIR__}/ensure-subagent.md") }}
end
