# CrystalDocs.org User Guide

## Table of Contents

- [Introduction](#introduction)
- [Browsing Documentation](#browsing-documentation)
- [Version Switching](#version-switching)
- [Reading Documentation](#reading-documentation)
- [For Library Authors](#for-library-authors)
- [Troubleshooting](#troubleshooting)

## Introduction

### What is CrystalDocs.org?

CrystalDocs.org is the official documentation hosting platform for Crystal shards. Similar to docs.rs for Rust, it automatically generates and hosts API documentation for all shards published on CrystalShards.org.

Every time you publish a shard or release a new version, CrystalDocs automatically:
1. Downloads your source code from GitHub
2. Runs `crystal doc` in a secure sandbox
3. Hosts the generated documentation
4. Makes it searchable and browsable

### Why Use CrystalDocs?

- **Automatic Generation**: No manual work required
- **Always Up-to-Date**: Rebuilds on every release
- **Version History**: Access docs for any published version
- **Full-Text Search**: Find classes, methods, and modules quickly
- **Cross-References**: Links between related shards and types
- **Syntax Highlighting**: Beautiful code examples
- **Zero Configuration**: Works out of the box

### How Documentation is Generated

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│ New Release  │─────▶│ Build Queue  │─────▶│ Sandboxed    │
│ on GitHub    │      │ (Background) │      │ crystal doc  │
└──────────────┘      └──────────────┘      └──────┬───────┘
                                                     │
┌──────────────┐      ┌──────────────┐             │
│ Browse Docs  │◀─────│ Static HTML  │◀────────────┘
│ Online       │      │ Storage      │
└──────────────┘      └──────────────┘
```

**Security**: Documentation builds run in isolated containers with:
- No network access
- Limited CPU and memory
- 10-minute timeout
- Read-only filesystem

## Browsing Documentation

### Finding Shard Documentation

**From CrystalShards.org:**
1. Visit any shard page on CrystalShards.org
2. Click the "Documentation" link in the sidebar
3. Automatically redirects to CrystalDocs.org

**Direct URL Pattern:**
```
https://crystaldocs.org/docs/{shard_name}/{version}
```

Examples:
- `https://crystaldocs.org/docs/kemal/latest`
- `https://crystaldocs.org/docs/lucky/1.0.0`
- `https://crystaldocs.org/docs/pg/0.24.0`

**Special URLs:**
- `/docs/{shard}/latest` - Always points to newest version
- `/docs/{shard}` - Redirects to latest version

### Homepage Navigation

CrystalDocs.org homepage features:

```
┌─────────────────────────────────────────┐
│ 🔍 Search Documentation                  │
│ ┌─────────────────────────────────────┐ │
│ │ Search shards, classes, methods...  │ │
│ └─────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│ 📚 Recently Updated                      │
│ • kemal (1.4.0) - 2 hours ago           │
│ • lucky (1.0.0) - 5 hours ago           │
│ • amber (0.36.0) - 1 day ago            │
├─────────────────────────────────────────┤
│ ⭐ Popular Shards                        │
│ • kemal - Web framework                 │
│ • lucky - Full-stack framework          │
│ • crystal-db - Database common API      │
└─────────────────────────────────────────┘
```

### Search Functionality

**Global Search:**
Type in the search box to find:
- Shard names: `kemal`
- Class names: `HTTP::Server`
- Method names: `render`, `redirect`
- Module names: `Kemal::Middleware`

**Search Filters:**
- **Shard**: Limit results to specific shard
- **Version**: Search within specific version
- **Type**: Filter by Class, Module, Method, Struct

**Example Searches:**
```
"HTTP::Request"           → Find HTTP::Request class
"render" in kemal         → Find render methods in Kemal
"initialize" version:1.0  → Find initializers in version 1.0
```

## Version Switching

### Understanding Versions

Each shard can have multiple documented versions:

```
┌─────────────────────────────────────┐
│ kemal Documentation                  │
├─────────────────────────────────────┤
│ Version: 1.4.0 ▼                    │
│ ├─ 1.4.0 (Latest) ← You are here   │
│ ├─ 1.3.0                            │
│ ├─ 1.2.0                            │
│ ├─ 1.1.0                            │
│ └─ 1.0.0                            │
└─────────────────────────────────────┘
```

### Version Selector

Located in the top navigation:

1. Click the version dropdown
2. Select desired version
3. Page reloads with selected version
4. URL updates: `/docs/kemal/1.3.0`

**Version Labels:**
- **(Latest)** - Most recent release
- **(Yanked)** - Removed from registry (docs preserved)
- **(Pre-release)** - Alpha, beta, or rc versions

### Version Comparison

To compare versions:

1. Open version 1.0.0 in one tab
2. Open version 2.0.0 in another tab
3. Compare API changes side-by-side

Useful for:
- Migration planning
- Breaking change identification
- Feature availability checking

### Default Versions

When you visit without version:
- `/docs/kemal` → Redirects to latest stable
- Skips pre-release versions by default
- Use `/docs/kemal/latest-pre` for pre-releases

## Reading Documentation

### Documentation Layout

Standard documentation structure:

```
┌─────────────────────────────────────────────────┐
│ Navigation Bar                                   │
│ ┌─────────┬───────────────────────────────────┐ │
│ │ Sidebar │ Main Content                       │ │
│ │         │                                    │ │
│ │ Classes │ # ClassName                        │ │
│ │ Modules │                                    │ │
│ │ Types   │ Description of the class...       │ │
│ │         │                                    │ │
│ │ Methods │ ## Methods                         │ │
│ │         │ ### #initialize                    │ │
│ │         │ Creates a new instance...          │ │
│ └─────────┴───────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### Navigation Sidebar

Left sidebar shows:

**Top-Level Types:**
```
📦 Kemal
  📂 Modules
    • Kemal::Middleware
    • Kemal::Handlers
  📂 Classes
    • Route
    • Context
    • StaticFileHandler
  📂 Structs
    • Response
```

Click any type to jump to its documentation.

### Main Content Area

Each documented item includes:

**1. Type Definition**
```crystal
class HTTP::Server
```

**2. Description**
```
HTTP server implementation with support for middleware,
routing, and static file serving.
```

**3. Example Usage**
```crystal
server = HTTP::Server.new do |context|
  context.response.content_type = "text/plain"
  context.response.print "Hello world!"
end

server.bind_tcp 8080
server.listen
```

**4. Instance Methods**
```crystal
#initialize(handler : HTTP::Handler)
#bind_tcp(host : String, port : Int32)
#listen
#close
```

**5. Class Methods**
```crystal
.new(handler : HTTP::Handler) : self
.new(&block) : self
```

### Code Examples

Documentation includes syntax-highlighted examples:

```crystal
# Create a new server
server = HTTP::Server.new do |context|
  context.response.content_type = "application/json"
  context.response.print %({"status": "ok"})
end

# Bind to port
server.bind_tcp "0.0.0.0", 3000

# Start listening
server.listen
```

**Copying Code:**
- Hover over code block
- Click "Copy" button in top-right
- Code copied to clipboard

### Type Links and Cross-References

CrystalDocs automatically links related types:

```crystal
def process(request : HTTP::Request) : HTTP::Response
#                    ^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^
#                    Links to class      Links to class
end
```

Click any type name to navigate to its documentation.

### Method Signatures

Methods show full type information:

```crystal
def fetch(url : String, headers : HTTP::Headers? = nil) : HTTP::Response
    ^^^^^                          ^^^^^^^^^^^^^^^^        ^^^^^^^^^^^^^
    Method name                    Optional param          Return type
```

**Understanding Signatures:**
- `:` separates parameter name from type
- `?` after type means nilable (can be nil)
- `= value` indicates default value
- `->` shows return type

### Instance vs Class Methods

**Instance Methods** (called on objects):
```crystal
#initialize(name : String)  # Note the # prefix
#save
#update
```

Usage:
```crystal
user = User.new("Alice")  # initialize
user.save                 # instance method
```

**Class Methods** (called on class):
```crystal
.find(id : Int32)  # Note the . prefix
.all
.create
```

Usage:
```crystal
User.find(1)     # class method
User.all         # class method
```

### Searching Within Documentation

**In-Page Search:**
- Press `Ctrl+F` (or `Cmd+F` on Mac)
- Searches current page only
- Highlights matches

**Site-Wide Search:**
- Use search box in navigation
- Searches all documented types
- Shows results across versions

### Keyboard Shortcuts

Speed up navigation:

- `S` - Focus search box
- `/` - Quick search
- `Esc` - Close search/modals
- `G` then `H` - Go to homepage
- `?` - Show all shortcuts

## For Library Authors

### Improving Your Documentation

CrystalDocs uses doc comments from your source code:

**Basic Documentation:**
```crystal
# Represents a user in the system.
class User
  # Creates a new user with the given name.
  #
  # ```
  # user = User.new("Alice")
  # ```
  def initialize(@name : String)
  end

  # Returns the user's uppercase name.
  def shout : String
    @name.upcase
  end
end
```

### Crystal Doc Syntax

**Paragraphs:**
```crystal
# This is paragraph one.
#
# This is paragraph two (blank comment line above).
```

**Code Examples:**
```crystal
# Example usage:
#
# ```
# server = Server.new
# server.start
# ```
```

**Lists:**
```crystal
# Supported formats:
# - JSON
# - XML
# - CSV
```

**Links:**
```crystal
# See `HTTP::Server` for details.
#                ^^^^^^^^^^^
# Automatically linked to class
```

**Bold and Italic:**
```crystal
# **Important**: This method is deprecated.
# Use *italics* for emphasis.
```

### Documentation Best Practices

**1. Document All Public APIs:**
```crystal
# ✅ Good - documented
def public_method
end

# ❌ Bad - no documentation
def another_public_method
end
```

**2. Include Examples:**
```crystal
# Fetches user by ID.
#
# ```
# user = User.find(123)
# puts user.name
# ```
def self.find(id : Int32)
end
```

**3. Explain Parameters:**
```crystal
# Sends an email.
#
# Parameters:
# - `to`: Recipient email address
# - `subject`: Email subject line
# - `body`: Email content (supports HTML)
def send_email(to : String, subject : String, body : String)
end
```

**4. Document Return Values:**
```crystal
# Saves the user to database.
#
# Returns `true` if saved successfully, `false` otherwise.
def save : Bool
end
```

**5. Note Side Effects:**
```crystal
# Deletes all expired sessions from the database.
#
# **Warning**: This operation is irreversible!
def self.cleanup_expired
end
```

**6. Show Error Conditions:**
```crystal
# Parses JSON string.
#
# Raises `JSON::ParseException` if invalid JSON.
def self.parse(json : String)
end
```

### Testing Documentation Locally

Before publishing, test docs locally:

```bash
# Generate documentation
crystal docs

# View in browser
open docs/index.html  # macOS
xdg-open docs/index.html  # Linux
```

Check for:
- [ ] All public classes/methods documented
- [ ] Code examples work correctly
- [ ] No broken cross-references
- [ ] Proper formatting

### Documentation Build Process

When you release a new version:

1. **GitHub Release Created** - You tag and push
2. **CrystalShards Notified** - Via webhook or polling
3. **Build Queued** - Added to documentation build queue
4. **Sandbox Created** - Isolated container spun up
5. **Code Downloaded** - GitHub repo cloned at version tag
6. **Dependencies Installed** - `shards install` runs
7. **Docs Generated** - `crystal docs` executes
8. **HTML Published** - Output uploaded to storage
9. **Search Indexed** - Content added to search database
10. **Live on CrystalDocs** - Available at `/docs/{shard}/{version}`

**Timeline**: Usually 5-15 minutes from release to published docs.

### Build Status

Check documentation build status:

1. Visit your shard page on CrystalShards.org
2. Look for "Documentation" section
3. Status indicators:
   - ✅ **Built** - Documentation available
   - 🔄 **Building** - In progress
   - ⏸️ **Queued** - Waiting for build
   - ❌ **Failed** - Build error (see logs)

### Failed Builds

Common causes and solutions:

**Syntax Errors:**
```
Error: Syntax error in src/my_shard.cr:42
```
Fix: Correct the syntax error and re-release.

**Missing Dependencies:**
```
Error: Can't find shard 'some_shard'
```
Fix: Ensure all dependencies are in `shard.yml`.

**Timeout:**
```
Error: Build exceeded 10-minute limit
```
Fix: Simplify or optimize your code. Contact support for large shards.

**Invalid Crystal Version:**
```
Error: Crystal version 0.36.0 required, found 1.0.0
```
Fix: Update `crystal:` field in shard.yml.

### Viewing Build Logs

If build fails:

1. Go to your shard on CrystalShards.org
2. Click "Documentation" → "Build Logs"
3. Review error messages
4. Fix issues in your code
5. Release new version

### Custom Documentation

While CrystalDocs is automatic, you can enhance it:

**README in Docs:**
Your `README.md` appears as homepage of docs (when properly formatted).

**Additional Pages:**
Create `.cr` files with doc comments to add conceptual documentation.

**Examples Directory:**
Include `examples/` folder with working examples (referenced in docs).

## Troubleshooting

### Common Issues

**"Documentation not found"**

Possible reasons:
1. Shard not published to CrystalShards.org yet
2. Documentation build still in progress (wait 5-15 min)
3. Build failed (check build logs)
4. Version doesn't exist

**"This page is outdated"**

Documentation reflects source at time of build. If you've:
- Updated code without releasing: Create new version tag
- Released recently: Wait for rebuild to complete
- Found outdated info: Report issue

**Search not finding my class**

Search index updates after build completes:
1. Wait 15-20 minutes after publishing
2. Try exact class name
3. Clear browser cache
4. Check if build succeeded

**Version not appearing**

Versions appear after successful build:
1. Verify version tag on GitHub
2. Check if version is in CrystalShards.org
3. Wait for build completion
4. Check build logs for errors

**Code examples not highlighted**

Ensure proper formatting:
````crystal
# Correct:
# ```
# code here
# ```

# Wrong:
# ``` crystal
# (no language specifier needed)
````

**Cross-reference links broken**

Links break if:
- Referenced type doesn't exist
- Typo in type name
- Type is in different shard (not resolved)

Fix: Use exact type names as defined.

### Performance Issues

**Slow page loads:**
1. Documentation for large shards takes time
2. Check your internet connection
3. Try different version (some are smaller)
4. Report persistent issues

**Search slow:**
1. First search initializes index (one-time delay)
2. Subsequent searches are fast
3. Clear browser cache if persistent

### Getting Help

**For Documentation Issues:**
1. Check [CrystalDocs Status](https://status.crystalshards.org)
2. Search [existing issues](https://github.com/crystalshards/crystaldocs/issues)
3. Email support@crystalshards.org with:
   - Shard name and version
   - What you expected
   - What actually happened
   - Build logs (if available)

**For Documentation Writing:**
1. Read [Crystal's documentation guide](https://crystal-lang.org/docs/conventions/documenting_code.html)
2. Study well-documented shards (e.g., `kemal`, `lucky`)
3. Ask on [Crystal Forum](https://forum.crystal-lang.org)

## Next Steps

Now that you understand CrystalDocs:

- **Browse**: Explore documentation of popular shards
- **Improve**: Enhance your shard's documentation
- **Contribute**: Help improve CrystalDocs [on GitHub](https://github.com/crystalshards/crystaldocs)
- **Share**: Link to your docs from README and project website

## Additional Resources

- **Crystal Documentation Guide**: [crystal-lang.org/docs/conventions/documenting_code.html](https://crystal-lang.org/docs/conventions/documenting_code.html)
- **CrystalShards Registry**: [crystalshards.org](https://crystalshards.org)
- **API Documentation**: [docs/api/README.md](../api/README.md)
- **Community Examples**: Browse popular shards for inspiration

---

**Last Updated**: 2025-10-09
**Guide Version**: 1.0.0

For feedback or corrections, please [open an issue](https://github.com/crystalshards/crystaldocs/issues).
