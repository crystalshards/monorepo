require "./statusline"

json = STDIN.gets_to_end
File.write("./.claude/input.local.json", json)
print Statusline.build(json)
