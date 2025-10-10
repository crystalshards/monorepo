# CrystalShards UI/UX Verification Plan - Playwright MCP

**Target URL**: https://crystalshards.org

**Status**: READY TO EXECUTE (awaiting deployment completion)

**Created**: 2025-10-10

**Purpose**: Comprehensive UI/UX verification of CrystalShards.org core pages (Homepage, Browse/Search, Package Detail) using Playwright MCP as required by CLAUDE.md Section 12.

---

## Table of Contents

1. [Overview](#overview)
2. [Page Inventory](#page-inventory)
3. [Verification Checklist Matrix](#verification-checklist-matrix)
4. [Detailed Test Scenarios](#detailed-test-scenarios)
5. [Playwright Command Sequences](#playwright-command-sequences)
6. [Success Criteria](#success-criteria)
7. [Issue Reporting Templates](#issue-reporting-templates)
8. [Execution Instructions](#execution-instructions)

---

## Overview

### Pages Under Test

1. **Homepage** (`/`)
   - Hero section with search
   - Featured shards grid
   - Recently updated shards grid
   - Statistics display

2. **Browse/Search Page** (`/shards`)
   - Search functionality
   - Filters (license, min stars, has docs)
   - Sorting (updated, popular, downloads, name)
   - Pagination
   - Results display

3. **Package Detail Page** (`/shards/:name`)
   - Package header with version badge
   - Installation instructions
   - README section
   - Dependencies list
   - Sidebar with links, versions, metadata

### Testing Approach

- **Snapshot First**: Use `browser_snapshot` for semantic structure inspection
- **Screenshot Second**: Use `browser_take_screenshot` only when visual verification needed
- **Error Detection**: Always check console messages and network requests
- **Responsive Testing**: Verify at mobile (375×667), tablet (768×1024), desktop (1920×1080)
- **Accessibility**: Check semantic HTML, ARIA labels, keyboard navigation

---

## Page Inventory

### Homepage Components

**Layout Structure:**
- `.hero` section
  - `.hero-content`
    - `.hero-title` (h1: "CrystalShards")
    - `.hero-subtitle` (p: description)
    - `SearchBar` component (large variant)
    - `.hero-stats` (total shards, total downloads)
- `.section` - Featured Shards
  - `h2`: "Featured Shards"
  - `.shard-grid` (ShardCard components)
- `.section` - Recently Updated
  - `h2`: "Recently Updated"
  - `.shard-grid` (ShardCard components)
  - `.section-footer` (View All Shards link)

**Interactive Elements:**
- Search form (input + button)
- Shard cards (clickable links to detail pages)
- "View All Shards →" link

**Expected Data:**
- `@total_shards` count displayed
- `@total_downloads` count displayed with formatting (1,000,000 format)
- `@featured_shards` array rendered as cards
- `@recent_shards` array rendered as cards

### Browse/Search Page Components

**Layout Structure:**
- `.section`
  - `.page-header` (h1, search results count)
  - `SearchBar` component
  - `.filters-section`
    - `.filters-form` (form with GET method)
      - `.filters-row`
        - Sort dropdown (#sort)
        - License filter (#license)
        - Min Stars filter (#min_stars)
        - Has Docs checkbox (has_docs)
        - Apply Filters button
        - Clear Filters button (if filters active)
  - `.shard-list` or `.empty-state`
  - `.pagination` (if total_count > per_page)

**Interactive Elements:**
- Search input (preserved from query param)
- Sort dropdown (updated, popular, downloads, name)
- License dropdown (All, MIT, Apache-2.0, BSD-3-Clause, GPL-3.0)
- Min Stars dropdown (Any, 10+, 50+, 100+, 500+)
- Has Docs checkbox
- Apply Filters button (type=submit)
- Clear Filters link
- Pagination links (Previous, Next)
- Shard cards (clickable)

**Form Behavior:**
- Preserves query param in hidden input
- Form submits to `/shards` via GET
- Filters build URL query string
- Clear Filters resets to base URL or query-only URL

**Empty States:**
- No shards: "No shards available yet."
- No search results: "No shards found matching your search."
- Includes "View All Shards" button if filters/query active

### Package Detail Page Components

**Layout Structure:**
- `.section`
  - `.shard-header`
    - `.shard-title-block`
      - `.shard-title` (h1: shard name)
      - `.badge` (version badge: "v1.2.3")
      - `.shard-description-large` (p: description)
    - `.shard-stats-block`
      - GitHub stars (⭐ count)
      - Total downloads
      - License
  - `.shard-content` (two-column layout)
    - `.shard-main`
      - `.shard-section` - Installation
        - `.code-block` (shard.yml snippet)
        - `.code-block` (shards install command)
      - `.shard-section` - README
        - `.readme-content`
      - `.shard-section` - Dependencies (if any)
        - Runtime Dependencies list
        - Development Dependencies list
      - `.shard-section` - Documentation (if docs_url exists)
        - Link to documentation
    - `.shard-sidebar`
      - `.sidebar-section` - Links
        - Repository, Homepage, Documentation
      - `.sidebar-section` - Versions
        - `.version-list` (up to 10 versions)
        - Version count footer if > 10
      - `.sidebar-section` - Provider
      - `.sidebar-section` - Metadata
        - Created, Updated, Crystal version

**Interactive Elements:**
- Repository link (external)
- Homepage link (external, if exists)
- Documentation link (external, if exists)
- Dependency links (internal, to other shard detail pages)
- Version list items (styled differently if yanked)

**Code Blocks:**
- Installation: shard.yml format
- Installation: CLI command
- Proper syntax highlighting expected

---

## Verification Checklist Matrix

| Category | Homepage | Browse/Search | Package Detail | Priority |
|----------|----------|---------------|----------------|----------|
| **Visual & Layout** | | | | |
| Page renders without broken layout | ✓ | ✓ | ✓ | CRITICAL |
| No overlapping elements | ✓ | ✓ | ✓ | CRITICAL |
| Images load with alt text | N/A | ✓ | ✓ | HIGH |
| Consistent spacing | ✓ | ✓ | ✓ | HIGH |
| Responsive (mobile 375×667) | ✓ | ✓ | ✓ | CRITICAL |
| Responsive (tablet 768×1024) | ✓ | ✓ | ✓ | CRITICAL |
| Responsive (desktop 1920×1080) | ✓ | ✓ | ✓ | CRITICAL |
| Typography readable | ✓ | ✓ | ✓ | HIGH |
| Color contrast accessible | ✓ | ✓ | ✓ | HIGH |
| **Navigation & Usability** | | | | |
| Header nav links work | ✓ | ✓ | ✓ | CRITICAL |
| Search redirects to /shards | ✓ | - | - | CRITICAL |
| Browse link navigates correctly | ✓ | ✓ | ✓ | CRITICAL |
| Shard cards link to detail pages | ✓ | ✓ | - | CRITICAL |
| Pagination works | - | ✓ | - | CRITICAL |
| "View All Shards" link works | ✓ | - | - | HIGH |
| **Interactive Elements** | | | | |
| Search input accepts text | ✓ | ✓ | - | CRITICAL |
| Search button submits form | ✓ | ✓ | - | CRITICAL |
| Filter dropdowns change values | - | ✓ | - | CRITICAL |
| Apply Filters submits form | - | ✓ | - | CRITICAL |
| Clear Filters resets URL | - | ✓ | - | CRITICAL |
| Buttons show hover states | ✓ | ✓ | ✓ | MEDIUM |
| Links show hover states | ✓ | ✓ | ✓ | MEDIUM |
| External links open in new tab | - | - | ✓ | HIGH |
| **Accessibility** | | | | |
| Semantic HTML structure | ✓ | ✓ | ✓ | CRITICAL |
| Form labels present | ✓ | ✓ | - | CRITICAL |
| ARIA labels on interactive elements | ✓ | ✓ | ✓ | HIGH |
| Keyboard navigation works | ✓ | ✓ | ✓ | HIGH |
| Focus indicators visible | ✓ | ✓ | ✓ | HIGH |
| Headings hierarchy correct (h1→h2→h3) | ✓ | ✓ | ✓ | HIGH |
| **Performance & Errors** | | | | |
| Page loads quickly (< 2s) | ✓ | ✓ | ✓ | HIGH |
| No JavaScript console errors | ✓ | ✓ | ✓ | CRITICAL |
| No 404 network errors | ✓ | ✓ | ✓ | CRITICAL |
| No 500 server errors | ✓ | ✓ | ✓ | CRITICAL |
| Loading states handled | - | ✓ | ✓ | MEDIUM |
| **Content** | | | | |
| Stats display correctly | ✓ | - | ✓ | HIGH |
| Numbers formatted (1,234,567) | ✓ | - | ✓ | MEDIUM |
| Dates formatted (Jan 1, 2025) | - | - | ✓ | MEDIUM |
| No placeholder/lorem ipsum text | ✓ | ✓ | ✓ | CRITICAL |
| Code blocks formatted correctly | - | - | ✓ | HIGH |
| Markdown rendered properly | - | - | ✓ | MEDIUM |
| Empty states show helpful messages | - | ✓ | - | HIGH |

---

## Detailed Test Scenarios

### Scenario 1: Homepage - First Visit (Happy Path)

**Objective**: Verify homepage loads correctly with all components visible and functional

**Steps**:
1. Navigate to `https://crystalshards.org`
2. Verify page loads without errors
3. Check semantic structure with snapshot
4. Verify hero section displays correctly
5. Verify search bar is present and functional
6. Verify stats display (total shards, downloads)
7. Verify featured shards grid displays
8. Verify recently updated shards grid displays
9. Test search functionality
10. Test "View All Shards" link

**Expected Results**:
- Page title: "Home"
- Hero title: "CrystalShards"
- Hero subtitle: "The official package registry for the Crystal programming language"
- Search input placeholder: "Search for shards..."
- Stats show numbers (> 0 if data exists)
- Featured shards grid with ShardCard components
- Recently updated shards grid with ShardCard components
- Search redirects to `/shards?query={input}`
- "View All Shards →" link navigates to `/shards`

**Critical Elements**:
- `.hero` section
- `.hero-title`
- `.hero-subtitle`
- `.search-form`
- `.hero-stats` with `.stat` elements
- `.shard-grid` (2 instances)
- `.view-all-link`

### Scenario 2: Browse/Search - Basic Search

**Objective**: Verify search functionality works end-to-end

**Steps**:
1. Navigate to homepage
2. Enter "http" in search input
3. Submit search form
4. Verify redirect to `/shards?query=http`
5. Check results display
6. Verify search input preserves query
7. Check search results count

**Expected Results**:
- URL changes to `/shards?query=http`
- Page title: "Search: http"
- Search input value: "http"
- Search results count: "Found X shard(s)"
- Results filtered by query
- Shard cards displayed in `.shard-list`

**Critical Elements**:
- `.page-header` with correct title
- `.search-results-count`
- `.search-input` with preserved value
- `.shard-list` with results

### Scenario 3: Browse/Search - Filters and Sorting

**Objective**: Verify all filter controls work correctly

**Steps**:
1. Navigate to `/shards`
2. Change sort to "Most Popular"
3. Select license "MIT"
4. Select min stars "50+"
5. Check "Has Documentation"
6. Click "Apply Filters"
7. Verify URL contains all params
8. Verify results update
9. Click "Clear Filters"
10. Verify filters reset

**Expected Results**:
- Sort dropdown changes to "Most Popular"
- License dropdown shows "MIT"
- Min Stars shows "50+"
- Has Docs checkbox is checked
- After apply: URL = `/shards?page=1&sort=popular&license=MIT&min_stars=50&has_docs=true`
- Results update accordingly
- "Clear Filters" button appears
- After clear: URL = `/shards`

**Critical Elements**:
- `#sort` dropdown
- `#license` dropdown
- `#min_stars` dropdown
- `input[name="has_docs"]` checkbox
- `button[type="submit"]` (Apply Filters)
- `.button` (Clear Filters link)

### Scenario 4: Browse/Search - Pagination

**Objective**: Verify pagination controls work correctly

**Steps**:
1. Navigate to `/shards` (assuming > 20 shards exist)
2. Verify pagination appears
3. Check page info: "Page 1 of X"
4. Click "Next →"
5. Verify URL: `/shards?page=2`
6. Verify page info: "Page 2 of X"
7. Click "← Previous"
8. Verify back to page 1

**Expected Results**:
- `.pagination` div visible if total_pages > 1
- "Next →" link present on page 1
- "← Previous" link appears on page 2+
- `.pagination-info` shows correct page numbers
- URL param updates correctly
- Results update for each page

**Critical Elements**:
- `.pagination`
- `.pagination-link` (Previous/Next)
- `.pagination-info`

### Scenario 5: Browse/Search - Empty State

**Objective**: Verify empty state displays when no results

**Steps**:
1. Navigate to `/shards?query=nonexistentshardxyz123`
2. Verify empty state displays
3. Check message text
4. Verify "View All Shards" button appears

**Expected Results**:
- `.empty-state` div visible
- Text: "No shards found matching your search."
- `.button` with "View All Shards" text
- Button links to `/shards`

**Critical Elements**:
- `.empty-state`
- `.button` (View All Shards)

### Scenario 6: Package Detail - Full Content

**Objective**: Verify package detail page displays all sections correctly

**Steps**:
1. Navigate to a package detail page (e.g., `/shards/lucky`)
2. Verify header section loads
3. Check version badge displays
4. Verify installation section
5. Check README section
6. Verify dependencies section (if any)
7. Check sidebar links
8. Verify versions list
9. Check metadata section

**Expected Results**:
- Page title: shard name (e.g., "lucky")
- Header shows shard name + version badge
- Description displays
- Stats show stars, downloads, license
- Installation code blocks formatted correctly
- README content displays
- Dependencies list (runtime + dev separated)
- Sidebar links work (repository, homepage, docs)
- Versions list shows up to 10 versions
- Metadata shows created, updated, crystal version

**Critical Elements**:
- `.shard-header`
- `.shard-title`
- `.badge` (version)
- `.shard-stats-block`
- `.code-block` (2 instances in Installation)
- `.readme-content`
- `.dependency-list`
- `.link-list` (sidebar links)
- `.version-list`
- `.sidebar-section` (metadata)

### Scenario 7: Package Detail - External Links

**Objective**: Verify external links open in new tabs with correct attributes

**Steps**:
1. Navigate to package detail page
2. Inspect repository link
3. Inspect homepage link (if exists)
4. Inspect documentation link (if exists)
5. Verify target="_blank" attribute

**Expected Results**:
- All external links have `target="_blank"`
- Repository URL matches shard.repository_url
- Homepage URL matches shard.homepage_url
- Documentation URL matches shard.documentation_url

**Critical Elements**:
- `a[href^="http"]` with `target="_blank"`

### Scenario 8: Responsive Design - Mobile (375×667)

**Objective**: Verify all pages are usable on mobile viewport

**Steps**:
1. Resize browser to 375×667
2. Navigate to homepage
3. Verify hero section stacks vertically
4. Check search bar is full width
5. Verify shard grid adapts (single column)
6. Navigate to `/shards`
7. Check filters stack vertically
8. Navigate to package detail
9. Verify two-column layout becomes single column
10. Check sidebar moves below main content

**Expected Results**:
- No horizontal scrolling
- All interactive elements accessible
- Text readable without zooming
- Buttons/links tappable (min 44×44px)
- Forms submit correctly
- Navigation remains functional

### Scenario 9: Responsive Design - Tablet (768×1024)

**Objective**: Verify layout adapts appropriately for tablet

**Steps**:
1. Resize browser to 768×1024
2. Navigate through all pages
3. Verify grid layouts (2 columns expected)
4. Check filter layout (may wrap or stay inline)
5. Verify sidebar remains beside main content

**Expected Results**:
- Grid shows 2 columns
- Filters may wrap but remain usable
- Sidebar stays in right column
- All interactions work

### Scenario 10: Responsive Design - Desktop (1920×1080)

**Objective**: Verify optimal layout on large screens

**Steps**:
1. Resize browser to 1920×1080
2. Navigate through all pages
3. Verify grid layouts (3-4 columns)
4. Check max-width constraints prevent excessive line length
5. Verify sidebar is appropriately sized

**Expected Results**:
- Content max-width prevents overly wide text
- Grid shows 3-4 columns
- Sidebar proportional to main content
- No excessive whitespace

### Scenario 11: Accessibility - Keyboard Navigation

**Objective**: Verify all interactive elements are keyboard accessible

**Steps**:
1. Navigate to homepage with keyboard only
2. Tab through all interactive elements
3. Verify focus indicators visible
4. Press Enter on search button
5. Navigate to browse page
6. Tab through filter controls
7. Press Space to toggle checkbox
8. Press Enter to submit form

**Expected Results**:
- Tab order is logical (top to bottom, left to right)
- Focus indicators clearly visible
- Enter/Space activate buttons
- All controls reachable via keyboard
- No keyboard traps

### Scenario 12: Performance - Load Times

**Objective**: Verify pages load within acceptable time

**Steps**:
1. Navigate to homepage
2. Measure load time
3. Navigate to browse page with filters
4. Measure load time
5. Navigate to package detail
6. Measure load time

**Expected Results**:
- Homepage: < 2 seconds
- Browse page: < 2 seconds
- Package detail: < 2 seconds
- No blocking resources

### Scenario 13: Error Detection - Console Errors

**Objective**: Ensure no JavaScript errors occur during normal usage

**Steps**:
1. Navigate to homepage
2. Check console messages
3. Interact with search
4. Navigate to browse
5. Apply filters
6. Navigate to package detail
7. Check console on each page

**Expected Results**:
- Zero console errors
- No uncaught exceptions
- No failed network requests (except expected 404s for optional resources)

---

## Playwright Command Sequences

### Quick Start - Smoke Test (All Pages)

**Purpose**: Fast verification that all pages load without critical errors

**Estimated Time**: 2-3 minutes

```bash
#!/bin/bash
# Smoke test - verify all pages load

echo "=== CrystalShards Smoke Test ==="

# Homepage
echo "Testing Homepage..."
mcp__playwright__browser_navigate --url "https://crystalshards.org"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

# Browse
echo "Testing Browse Page..."
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

# Package Detail (assuming 'lucky' shard exists)
echo "Testing Package Detail..."
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards/lucky"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

echo "✓ Smoke test complete"
```

### Full Test Suite - Homepage

**Purpose**: Comprehensive verification of homepage

**Estimated Time**: 10-15 minutes

```bash
#!/bin/bash
# Full homepage verification

echo "=== Homepage Verification ==="

# 1. Navigate to homepage
echo "Step 1: Navigate to homepage"
mcp__playwright__browser_navigate --url "https://crystalshards.org"

# 2. Take initial snapshot
echo "Step 2: Capture accessibility snapshot"
mcp__playwright__browser_snapshot

# 3. Check console errors
echo "Step 3: Check for console errors"
mcp__playwright__browser_console_messages --onlyErrors true

# 4. Take desktop screenshot
echo "Step 4: Screenshot (desktop)"
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-homepage-desktop.png"

# 5. Verify hero section visible
echo "Step 5: Verify hero section"
# Note: Use snapshot output to get element refs
# Example: Check for hero-title element in snapshot

# 6. Test search functionality
echo "Step 6: Test search input"
# Get search input ref from snapshot, then:
# mcp__playwright__browser_type \
#   --element "search input" \
#   --ref "[REF_FROM_SNAPSHOT]" \
#   --text "http client"

# 7. Submit search
echo "Step 7: Submit search form"
# mcp__playwright__browser_click \
#   --element "search button" \
#   --ref "[BUTTON_REF_FROM_SNAPSHOT]"

# 8. Wait for redirect
echo "Step 8: Wait for search results"
# mcp__playwright__browser_wait_for --text "Found"

# 9. Verify redirect
echo "Step 9: Capture search results"
# mcp__playwright__browser_snapshot

# 10. Navigate back to homepage
echo "Step 10: Navigate back"
mcp__playwright__browser_navigate_back

# 11. Test "View All Shards" link
echo "Step 11: Test View All Shards link"
# Get link ref from snapshot, then:
# mcp__playwright__browser_click \
#   --element "View All Shards link" \
#   --ref "[LINK_REF_FROM_SNAPSHOT]"

# 12. Verify navigation to /shards
echo "Step 12: Verify browse page loads"
# mcp__playwright__browser_snapshot

# 13. Navigate back for responsive tests
mcp__playwright__browser_navigate --url "https://crystalshards.org"

# 14. Test mobile viewport
echo "Step 13: Test mobile viewport (375×667)"
mcp__playwright__browser_resize --width 375 --height 667
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-homepage-mobile.png"

# 15. Test tablet viewport
echo "Step 14: Test tablet viewport (768×1024)"
mcp__playwright__browser_resize --width 768 --height 1024
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-homepage-tablet.png"

# 16. Reset to desktop
echo "Step 15: Reset to desktop viewport"
mcp__playwright__browser_resize --width 1920 --height 1080

# 17. Check network requests
echo "Step 16: Check network requests"
mcp__playwright__browser_network_requests

echo "✓ Homepage verification complete"
```

### Full Test Suite - Browse/Search Page

**Purpose**: Comprehensive verification of browse and search functionality

**Estimated Time**: 15-20 minutes

```bash
#!/bin/bash
# Full browse/search verification

echo "=== Browse/Search Page Verification ==="

# 1. Navigate to browse page
echo "Step 1: Navigate to browse page"
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"

# 2. Capture initial state
echo "Step 2: Capture accessibility snapshot"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

# 3. Screenshot
echo "Step 3: Screenshot (desktop)"
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-browse-desktop.png"

# 4. Test search input
echo "Step 4: Test search functionality"
# Get search input ref from snapshot
# mcp__playwright__browser_type \
#   --element "search input" \
#   --ref "[SEARCH_INPUT_REF]" \
#   --text "http"

# 5. Submit search
# mcp__playwright__browser_press_key --key "Enter"

# 6. Wait for results
# mcp__playwright__browser_wait_for --text "Found"

# 7. Verify search results
echo "Step 5: Verify search results"
# mcp__playwright__browser_snapshot

# 8. Navigate back to browse
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"

# 9. Test sorting
echo "Step 6: Test sorting dropdown"
# Get sort dropdown ref from snapshot
# mcp__playwright__browser_select_option \
#   --element "sort dropdown" \
#   --ref "[SORT_REF]" \
#   --values '["popular"]'

# 10. Apply filters (submit form)
# Note: Selecting dropdown may auto-submit depending on implementation
# If not, click "Apply Filters" button

# 11. Verify sort in URL
echo "Step 7: Verify URL contains sort param"
# mcp__playwright__browser_snapshot

# 12. Test license filter
echo "Step 8: Test license filter"
# mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
# mcp__playwright__browser_select_option \
#   --element "license dropdown" \
#   --ref "[LICENSE_REF]" \
#   --values '["MIT"]'

# 13. Test min stars filter
echo "Step 9: Test min stars filter"
# mcp__playwright__browser_select_option \
#   --element "min stars dropdown" \
#   --ref "[MIN_STARS_REF]" \
#   --values '["50"]'

# 14. Test has docs checkbox
echo "Step 10: Test has docs checkbox"
# mcp__playwright__browser_click \
#   --element "has docs checkbox" \
#   --ref "[HAS_DOCS_REF]"

# 15. Apply all filters
echo "Step 11: Apply all filters"
# mcp__playwright__browser_click \
#   --element "Apply Filters button" \
#   --ref "[APPLY_BUTTON_REF]"

# 16. Verify URL contains all params
echo "Step 12: Verify filtered URL"
# mcp__playwright__browser_snapshot

# 17. Test Clear Filters
echo "Step 13: Test Clear Filters"
# mcp__playwright__browser_click \
#   --element "Clear Filters button" \
#   --ref "[CLEAR_FILTERS_REF]"

# 18. Verify filters cleared
echo "Step 14: Verify filters cleared"
# mcp__playwright__browser_snapshot

# 19. Test pagination (if exists)
echo "Step 15: Test pagination"
# mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
# Check if pagination exists in snapshot
# If yes:
# mcp__playwright__browser_click \
#   --element "Next page link" \
#   --ref "[NEXT_REF]"
# mcp__playwright__browser_snapshot
# mcp__playwright__browser_click \
#   --element "Previous page link" \
#   --ref "[PREV_REF]"

# 20. Test empty state
echo "Step 16: Test empty state"
mcp__playwright__browser_navigate \
  --url "https://crystalshards.org/shards?query=nonexistentshardxyz123"
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-browse-empty.png"

# 21. Mobile responsive
echo "Step 17: Test mobile viewport"
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
mcp__playwright__browser_resize --width 375 --height 667
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-browse-mobile.png"

# 22. Tablet responsive
echo "Step 18: Test tablet viewport"
mcp__playwright__browser_resize --width 768 --height 1024
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-browse-tablet.png"

# 23. Reset viewport
mcp__playwright__browser_resize --width 1920 --height 1080

# 24. Check network requests
echo "Step 19: Check network requests"
mcp__playwright__browser_network_requests

echo "✓ Browse/Search verification complete"
```

### Full Test Suite - Package Detail Page

**Purpose**: Comprehensive verification of package detail page

**Estimated Time**: 10-15 minutes

```bash
#!/bin/bash
# Full package detail verification
# NOTE: Replace 'lucky' with an actual shard name that exists in the database

echo "=== Package Detail Page Verification ==="

SHARD_NAME="lucky"  # Change this to an actual shard

# 1. Navigate to package detail
echo "Step 1: Navigate to package detail"
mcp__playwright__browser_navigate \
  --url "https://crystalshards.org/shards/${SHARD_NAME}"

# 2. Capture initial state
echo "Step 2: Capture accessibility snapshot"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

# 3. Screenshot
echo "Step 3: Screenshot (desktop)"
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-detail-${SHARD_NAME}-desktop.png"

# 4. Verify header section
echo "Step 4: Verify header section visible"
# Check snapshot for:
# - .shard-title (h1)
# - .badge (version)
# - .shard-description-large
# - .shard-stats-block

# 5. Verify installation section
echo "Step 5: Verify installation section"
# Check snapshot for:
# - .code-block elements (should be 2)
# - Pre/code tags with shard.yml content

# 6. Verify README section
echo "Step 6: Verify README section"
# Check snapshot for:
# - .readme-content
# - Description text

# 7. Verify dependencies section (if any)
echo "Step 7: Check dependencies section"
# Check snapshot for:
# - .dependency-list
# - Runtime/dev dependencies separated

# 8. Test dependency links (if any)
echo "Step 8: Test dependency links"
# If dependencies exist in snapshot:
# mcp__playwright__browser_click \
#   --element "first dependency link" \
#   --ref "[DEPENDENCY_REF]"
# mcp__playwright__browser_snapshot
# mcp__playwright__browser_navigate_back

# 9. Verify sidebar - Links section
echo "Step 9: Verify sidebar links"
# Check snapshot for:
# - Repository link
# - Homepage link (if exists)
# - Documentation link (if exists)

# 10. Test external links have target="_blank"
echo "Step 10: Verify external links"
# Use browser_evaluate to check:
# mcp__playwright__browser_evaluate \
#   --function "() => {
#     const links = document.querySelectorAll('a[href^=\"http\"]');
#     return Array.from(links).every(link => link.target === '_blank');
#   }"

# 11. Verify versions section
echo "Step 11: Verify versions section"
# Check snapshot for:
# - .version-list
# - Version numbers
# - Release dates

# 12. Verify metadata section
echo "Step 12: Verify metadata section"
# Check snapshot for:
# - Created date
# - Updated date
# - Crystal version (if exists)

# 13. Test mobile viewport
echo "Step 13: Test mobile viewport"
mcp__playwright__browser_resize --width 375 --height 667
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-detail-${SHARD_NAME}-mobile.png"

# 14. Verify sidebar moves below main content on mobile
echo "Step 14: Verify responsive layout (sidebar below main)"
# Check snapshot for layout changes

# 15. Test tablet viewport
echo "Step 15: Test tablet viewport"
mcp__playwright__browser_resize --width 768 --height 1024
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-detail-${SHARD_NAME}-tablet.png"

# 16. Reset viewport
mcp__playwright__browser_resize --width 1920 --height 1080

# 17. Check network requests
echo "Step 16: Check network requests"
mcp__playwright__browser_network_requests

# 18. Test navigation to another shard
echo "Step 17: Test navigation between shards"
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
# Click on a different shard card
# mcp__playwright__browser_click \
#   --element "first shard card link" \
#   --ref "[SHARD_CARD_REF]"
# mcp__playwright__browser_snapshot

echo "✓ Package Detail verification complete"
```

### Cross-Page Navigation Test

**Purpose**: Verify navigation flow between all pages

**Estimated Time**: 5-10 minutes

```bash
#!/bin/bash
# Cross-page navigation verification

echo "=== Cross-Page Navigation Verification ==="

# 1. Start at homepage
echo "Step 1: Start at homepage"
mcp__playwright__browser_navigate --url "https://crystalshards.org"
mcp__playwright__browser_snapshot

# 2. Click "Browse Shards" in header
echo "Step 2: Navigate to Browse via header"
# mcp__playwright__browser_click \
#   --element "Browse Shards nav link" \
#   --ref "[NAV_BROWSE_REF]"
# mcp__playwright__browser_snapshot

# 3. Verify on /shards
echo "Step 3: Verify on browse page"
# Check URL and snapshot

# 4. Click homepage link in header
echo "Step 4: Navigate back to homepage via header"
# mcp__playwright__browser_click \
#   --element "Home nav link" \
#   --ref "[NAV_HOME_REF]"
# mcp__playwright__browser_snapshot

# 5. Click logo to go home
echo "Step 5: Navigate via logo"
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
# mcp__playwright__browser_click \
#   --element "CrystalShards logo" \
#   --ref "[LOGO_REF]"
# mcp__playwright__browser_snapshot

# 6. Search from homepage
echo "Step 6: Search from homepage"
mcp__playwright__browser_navigate --url "https://crystalshards.org"
# Type and submit search
# Verify redirect to /shards?query=...

# 7. Click shard card from search results
echo "Step 7: Navigate to shard detail from search"
# Click first result
# Verify on /shards/:name

# 8. Navigate back
echo "Step 8: Test browser back button"
mcp__playwright__browser_navigate_back
mcp__playwright__browser_snapshot

# 9. Click "View All Shards" from homepage
echo "Step 9: Navigate via View All Shards"
mcp__playwright__browser_navigate --url "https://crystalshards.org"
# Click View All Shards link
# Verify on /shards

# 10. Test external documentation link
echo "Step 10: Verify external docs link (should not navigate)"
# Note: External links open in new tab, so we can't follow them
# Instead, verify the link exists and has correct attributes

echo "✓ Cross-page navigation complete"
```

### Accessibility Test Suite

**Purpose**: Verify keyboard navigation and accessibility

**Estimated Time**: 10-15 minutes

```bash
#!/bin/bash
# Accessibility verification

echo "=== Accessibility Verification ==="

# 1. Homepage keyboard navigation
echo "Step 1: Test keyboard navigation on homepage"
mcp__playwright__browser_navigate --url "https://crystalshards.org"
mcp__playwright__browser_snapshot

# 2. Tab through elements
echo "Step 2: Tab through interactive elements"
# mcp__playwright__browser_press_key --key "Tab"
# Repeat Tab presses to move through all focusable elements
# Take snapshots to verify focus indicators

# 3. Activate search with Enter
echo "Step 3: Activate search with keyboard"
# Navigate to search input via Tab
# mcp__playwright__browser_press_key --key "Enter"

# 4. Check focus indicators
echo "Step 4: Verify focus indicators visible"
# Use browser_evaluate to check computed styles
# mcp__playwright__browser_evaluate \
#   --function "() => {
#     const focused = document.activeElement;
#     const styles = window.getComputedStyle(focused);
#     return {
#       outline: styles.outline,
#       outlineColor: styles.outlineColor,
#       outlineWidth: styles.outlineWidth
#     };
#   }"

# 5. Browse page keyboard navigation
echo "Step 5: Test keyboard navigation on browse page"
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
mcp__playwright__browser_snapshot

# 6. Tab to filter controls
echo "Step 6: Navigate to filter controls"
# Tab to each filter control
# Test Space/Enter activation

# 7. Test checkbox with Space
echo "Step 7: Test checkbox with Space key"
# Tab to "Has Docs" checkbox
# mcp__playwright__browser_press_key --key "Space"
# Verify checkbox toggles

# 8. Submit form with Enter
echo "Step 8: Submit form with Enter"
# Focus on submit button
# mcp__playwright__browser_press_key --key "Enter"

# 9. Check heading hierarchy
echo "Step 9: Verify heading hierarchy"
mcp__playwright__browser_navigate --url "https://crystalshards.org"
# mcp__playwright__browser_evaluate \
#   --function "() => {
#     const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
#     return Array.from(headings).map(h => ({
#       tag: h.tagName,
#       text: h.textContent.trim()
#     }));
#   }"

# 10. Check for ARIA labels
echo "Step 10: Check ARIA labels"
# mcp__playwright__browser_evaluate \
#   --function "() => {
#     const interactive = document.querySelectorAll('button, a, input, select, textarea');
#     return Array.from(interactive).map(el => ({
#       tag: el.tagName,
#       ariaLabel: el.getAttribute('aria-label'),
#       ariaLabelledBy: el.getAttribute('aria-labelledby'),
#       text: el.textContent?.trim() || el.value
#     }));
#   }"

# 11. Check alt text on images
echo "Step 11: Verify alt text on images"
# mcp__playwright__browser_evaluate \
#   --function "() => {
#     const images = document.querySelectorAll('img');
#     return Array.from(images).map(img => ({
#       src: img.src,
#       alt: img.alt,
#       hasAlt: img.hasAttribute('alt')
#     }));
#   }"

# 12. Check color contrast
echo "Step 12: Check color contrast (manual review)"
mcp__playwright__browser_take_screenshot \
  --filename "crystalshards-contrast-check.png"

echo "✓ Accessibility verification complete"
echo "Note: Manual review recommended for color contrast and screen reader compatibility"
```

### Performance Test Suite

**Purpose**: Verify page load performance

**Estimated Time**: 5-10 minutes

```bash
#!/bin/bash
# Performance verification

echo "=== Performance Verification ==="

# 1. Measure homepage load time
echo "Step 1: Measure homepage load time"
mcp__playwright__browser_navigate --url "https://crystalshards.org"
# mcp__playwright__browser_evaluate \
#   --function "() => {
#     const perfData = window.performance.timing;
#     const pageLoadTime = perfData.loadEventEnd - perfData.navigationStart;
#     return {
#       pageLoadTime: pageLoadTime,
#       domContentLoaded: perfData.domContentLoadedEventEnd - perfData.navigationStart,
#       dns: perfData.domainLookupEnd - perfData.domainLookupStart,
#       tcp: perfData.connectEnd - perfData.connectStart,
#       ttfb: perfData.responseStart - perfData.navigationStart
#     };
#   }"

# 2. Measure browse page load time
echo "Step 2: Measure browse page load time"
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
# Repeat performance measurement

# 3. Measure package detail load time
echo "Step 3: Measure package detail load time"
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards/lucky"
# Repeat performance measurement

# 4. Check for blocking resources
echo "Step 4: Check for blocking resources"
mcp__playwright__browser_network_requests
# Review network waterfall for:
# - Blocking scripts/styles
# - Large resources
# - Slow API calls

# 5. Check for lazy loading
echo "Step 5: Verify lazy loading (if implemented)"
# Check if images use loading="lazy"
# mcp__playwright__browser_evaluate \
#   --function "() => {
#     const images = document.querySelectorAll('img');
#     return Array.from(images).map(img => ({
#       src: img.src,
#       loading: img.loading
#     }));
#   }"

echo "✓ Performance verification complete"
```

---

## Success Criteria

### Critical Success Criteria (MUST PASS)

All of the following MUST pass for UI verification to be considered successful:

1. **Zero Console Errors** on all pages
   - No uncaught JavaScript exceptions
   - No 500 server errors
   - No 404 errors for critical resources

2. **Pages Load Successfully**
   - Homepage loads and displays content
   - Browse page loads and displays content
   - Package detail page loads and displays content

3. **Core Functionality Works**
   - Search redirects to `/shards?query=...`
   - Filters submit and update URL
   - Pagination navigates between pages
   - Shard cards link to detail pages
   - Navigation links work

4. **Responsive Design Functions**
   - Mobile (375×667): No horizontal scroll, all elements accessible
   - Tablet (768×1024): Layout adapts appropriately
   - Desktop (1920×1080): Optimal layout with max-width constraints

5. **Semantic HTML Structure**
   - Proper heading hierarchy (h1 → h2 → h3)
   - Form labels present
   - No major accessibility violations

6. **No Broken Layouts**
   - No overlapping elements
   - No content overflow
   - Consistent spacing

### High Priority Success Criteria (SHOULD PASS)

The following should pass, but are not blockers if minor issues exist:

1. **External Links**
   - All external links have `target="_blank"`
   - Links point to correct URLs

2. **Empty States**
   - Empty state displays correctly
   - Helpful messages shown

3. **Keyboard Navigation**
   - Tab order is logical
   - Focus indicators visible
   - Enter/Space activate controls

4. **Performance**
   - Pages load in < 2 seconds
   - No blocking resources

5. **Content Formatting**
   - Numbers formatted with commas
   - Dates formatted correctly
   - Code blocks display properly

### Medium Priority Success Criteria (NICE TO HAVE)

The following are nice to have but not critical:

1. **Hover States**
   - Links and buttons show hover effects
   - Interactive feedback

2. **Loading States**
   - Loading indicators if async operations exist

3. **Metadata**
   - All sidebar metadata displays correctly

4. **Accessibility Enhancements**
   - ARIA labels on all interactive elements
   - Color contrast meets WCAG AA

### Automated Success Criteria Checklist

Use this checklist during verification:

```markdown
## CrystalShards UI Verification Checklist

### Critical (Must Pass)
- [ ] Homepage loads without errors
- [ ] Browse page loads without errors
- [ ] Package detail loads without errors
- [ ] Zero console errors on all pages
- [ ] Zero 500 errors in network requests
- [ ] Search functionality works
- [ ] Filters submit and update URL
- [ ] Shard cards link to detail pages
- [ ] Navigation links work
- [ ] Mobile viewport (375×667) usable
- [ ] Tablet viewport (768×1024) usable
- [ ] Desktop viewport (1920×1080) usable
- [ ] No horizontal scrolling on mobile
- [ ] Proper heading hierarchy
- [ ] No overlapping elements
- [ ] No content overflow

### High Priority (Should Pass)
- [ ] External links have target="_blank"
- [ ] Empty state displays correctly
- [ ] Keyboard navigation works
- [ ] Focus indicators visible
- [ ] Pages load in < 2 seconds
- [ ] Numbers formatted correctly
- [ ] Dates formatted correctly
- [ ] Code blocks display properly
- [ ] Pagination works
- [ ] Clear Filters button works

### Medium Priority (Nice to Have)
- [ ] Links show hover states
- [ ] Buttons show hover states
- [ ] ARIA labels present
- [ ] Color contrast meets WCAG AA
- [ ] Version list displays correctly
- [ ] Dependencies list displays correctly
- [ ] Sidebar metadata displays

### Additional Checks
- [ ] No placeholder/lorem ipsum text
- [ ] Images have alt text (if any)
- [ ] Forms have labels
- [ ] No broken images
- [ ] Stats display correctly
```

---

## Issue Reporting Templates

### GitHub Issue Template - UI Bug

Use this template when creating issues for UI problems found during verification:

```markdown
---
title: "UI Issue: [Brief description]"
labels: bug, ui, crystalshards
assignees:
---

## Description

[Clear description of the UI issue]

## Page/Component Affected

- **Page**: [Homepage / Browse / Package Detail]
- **Component**: [Specific component or section]
- **URL**: [Full URL where issue occurs]

## Steps to Reproduce

1. Navigate to [URL]
2. [Action 1]
3. [Action 2]
4. [Observe issue]

## Expected Behavior

[What should happen]

## Actual Behavior

[What actually happens]

## Screenshots

[Attach Playwright screenshots showing the issue]

## Browser/Viewport

- **Browser**: Playwright (Chromium)
- **Viewport**: [e.g., 375×667 (mobile) / 1920×1080 (desktop)]

## Console Errors

```
[Paste any console errors if applicable]
```

## Network Errors

```
[Paste any failed network requests if applicable]
```

## Severity

- [ ] Critical - Blocks core functionality
- [ ] High - Impacts user experience significantly
- [ ] Medium - Noticeable but workaround exists
- [ ] Low - Minor cosmetic issue

## Additional Context

[Any other relevant information]

## Verification Method

Discovered during Playwright UI/UX verification (CLAUDE.md Section 12)

---

**Playwright Snapshot**: [Link to snapshot output if available]
```

### GitHub Issue Template - Accessibility Issue

Use this template for accessibility-specific issues:

```markdown
---
title: "A11y Issue: [Brief description]"
labels: bug, accessibility, crystalshards
assignees:
---

## Accessibility Issue

[Clear description of the accessibility problem]

## WCAG Guideline Violated

- **Guideline**: [e.g., 1.4.3 Contrast (Minimum)]
- **Level**: [A / AA / AAA]
- **Success Criterion**: [Link to WCAG guideline]

## Page/Component Affected

- **Page**: [Homepage / Browse / Package Detail]
- **Element**: [Specific element with issue]
- **URL**: [Full URL where issue occurs]

## Impact

[Who is affected? Screen reader users, keyboard users, low vision users, etc.]

## Steps to Reproduce

1. Navigate to [URL]
2. [Action with keyboard / screen reader / etc.]
3. [Observe issue]

## Expected Behavior

[What should happen for accessibility]

## Actual Behavior

[What actually happens]

## Suggested Fix

[How to fix the issue, if known]

## Screenshots/Code

[Visual evidence or code snippet showing the issue]

## Testing Method

- [ ] Keyboard navigation
- [ ] Screen reader (specify which)
- [ ] Accessibility snapshot
- [ ] Automated tool (specify which)

## Severity

- [ ] Critical - Prevents access to functionality
- [ ] High - Significant barrier to access
- [ ] Medium - Makes access difficult
- [ ] Low - Minor inconvenience

## Additional Context

[Any other relevant information]

## Verification Method

Discovered during Playwright UI/UX verification (CLAUDE.md Section 12)
```

### GitHub Issue Template - Performance Issue

Use this template for performance-related issues:

```markdown
---
title: "Performance Issue: [Brief description]"
labels: bug, performance, crystalshards
assignees:
---

## Performance Issue

[Clear description of the performance problem]

## Page Affected

- **Page**: [Homepage / Browse / Package Detail]
- **URL**: [Full URL where issue occurs]

## Metrics

- **Page Load Time**: [e.g., 5.2 seconds]
- **Time to First Byte (TTFB)**: [e.g., 1.8 seconds]
- **DOM Content Loaded**: [e.g., 3.5 seconds]
- **Fully Loaded**: [e.g., 5.2 seconds]

## Expected Performance

- **Target Load Time**: < 2 seconds

## Bottlenecks Identified

[What's causing the slow performance?]

- [ ] Slow API response
- [ ] Large resource files
- [ ] Blocking scripts/styles
- [ ] Too many network requests
- [ ] Database query performance
- [ ] Other: [specify]

## Network Requests

```
[Paste slow network requests from browser_network_requests]
```

## Suggested Optimizations

[How to improve performance]

## Impact

[How does this affect users?]

## Severity

- [ ] Critical - Unusable on slow connections
- [ ] High - Significantly impacts UX
- [ ] Medium - Noticeable but tolerable
- [ ] Low - Minor performance concern

## Additional Context

[Any other relevant information]

## Verification Method

Discovered during Playwright UI/UX verification (CLAUDE.md Section 12)

---

**Performance Data**: [Link to detailed performance analysis if available]
```

### Quick Issue Creation Commands

For rapid issue creation during verification:

```bash
# Create UI bug issue
gh issue create \
  --title "UI Issue: [description]" \
  --label "bug,ui,crystalshards" \
  --body-file issue-body.md

# Create accessibility issue
gh issue create \
  --title "A11y Issue: [description]" \
  --label "bug,accessibility,crystalshards" \
  --body-file issue-body.md

# Create performance issue
gh issue create \
  --title "Performance Issue: [description]" \
  --label "bug,performance,crystalshards" \
  --body-file issue-body.md
```

---

## Execution Instructions

### Prerequisites

1. **Deployment Must Be Complete**
   - CrystalShards deployment successful
   - https://crystalshards.org accessible
   - Backend API functional
   - Database seeded with test data

2. **Playwright MCP Available**
   - Playwright MCP server running
   - Browser installed (run `mcp__playwright__browser_install` if needed)

3. **GitHub CLI Configured**
   - `gh auth status` shows authenticated
   - Access to crystalshards/crystalshards-claude repo

### Execution Order

Execute test suites in this order for comprehensive coverage:

1. **Smoke Test** (2-3 minutes)
   - Verifies all pages load
   - Quick sanity check

2. **Homepage Full Test** (10-15 minutes)
   - Comprehensive homepage verification
   - Tests search, navigation, responsiveness

3. **Browse/Search Full Test** (15-20 minutes)
   - Tests search, filters, sorting, pagination
   - Verifies empty states

4. **Package Detail Full Test** (10-15 minutes)
   - Verifies all package detail sections
   - Tests external links, dependencies

5. **Cross-Page Navigation Test** (5-10 minutes)
   - Tests navigation between pages
   - Verifies header/footer consistency

6. **Accessibility Test** (10-15 minutes)
   - Keyboard navigation
   - Semantic HTML
   - ARIA labels

7. **Performance Test** (5-10 minutes)
   - Load time measurements
   - Network request analysis

**Total Estimated Time**: 60-90 minutes

### Execution Workflow

**Step 1: Verify Deployment Status**

```bash
# Check if CrystalShards is accessible
curl -I https://crystalshards.org

# Expected: HTTP 200 OK
```

**Step 2: Install Playwright Browser (if needed)**

```bash
mcp__playwright__browser_install
```

**Step 3: Run Smoke Test**

Execute the smoke test script to verify all pages load:

```bash
# Navigate to homepage
mcp__playwright__browser_navigate --url "https://crystalshards.org"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

# Navigate to browse
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

# Navigate to package detail (replace with actual shard)
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards/lucky"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true
```

**Step 4: Analyze Smoke Test Results**

- Review snapshots for semantic structure
- Check console messages for errors
- If critical errors found, create GitHub issues immediately
- If smoke test passes, proceed to full test suites

**Step 5: Execute Full Test Suites**

Follow the command sequences in the "Playwright Command Sequences" section above, customizing based on actual page content (element refs from snapshots).

**Step 6: Document Findings**

For each issue found:

1. Take screenshot: `mcp__playwright__browser_take_screenshot`
2. Capture snapshot: `mcp__playwright__browser_snapshot`
3. Save console errors: `mcp__playwright__browser_console_messages`
4. Create GitHub issue using templates above
5. Add to verification results document

**Step 7: Create Verification Summary**

After all tests complete, create a summary document:

```markdown
# CrystalShards UI Verification Results

**Date**: 2025-10-10
**Verifier**: Claude Agent
**Target**: https://crystalshards.org
**Status**: [PASS / PASS WITH ISSUES / FAIL]

## Summary

- **Total Tests**: [number]
- **Passed**: [number]
- **Failed**: [number]
- **Issues Created**: [number]

## Critical Issues

[List any critical issues that block functionality]

## High Priority Issues

[List high priority issues]

## Medium Priority Issues

[List medium priority issues]

## Screenshots

[Links to screenshots]

## Recommendations

[Next steps or recommendations]

## Success Criteria Met

- [x] All pages load without errors
- [x] Core functionality works
- [ ] [Any criteria not met]

## Conclusion

[Overall assessment of UI/UX quality]
```

**Step 8: Comment on GitHub Issues**

Add verification results to relevant GitHub issues:

```bash
# Find the issue for CrystalShards UI implementation
gh issue list --label "crystalshards,ui" --state open

# Add comment with verification results
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## UI/UX Verification Complete

Playwright verification completed per CLAUDE.md Section 12.

**Status**: [PASS / PASS WITH ISSUES / FAIL]

**Summary**:
- Homepage: [status]
- Browse/Search: [status]
- Package Detail: [status]

**Issues Found**: [number]

**Critical Issues**: [list or "None"]

**Recommendations**: [any recommendations]

**Verification Results**: [link to summary document]

**Screenshots**: [links]
EOF
)"
```

### Troubleshooting

**Issue: Browser not installed**

```bash
mcp__playwright__browser_install
```

**Issue: Page not loading (timeout)**

```bash
# Increase timeout or check deployment status
curl -I https://crystalshards.org
kubectl get pods -n crystalshards
```

**Issue: Element refs not found in snapshot**

- Review snapshot output carefully
- Element refs are in the format `[ref=...]`
- Copy exact ref string for use in click/type commands

**Issue: Too many screenshots**

- Focus on critical issues only
- Use snapshots instead of screenshots for most checks
- Only screenshot when visual verification needed

**Issue: Network requests show errors**

- Document as GitHub issue
- Include request URL, status code, error message
- Check if blocking or cosmetic

### After Verification

1. **Close browser**: `mcp__playwright__browser_close`
2. **Create summary document** (see Step 7 above)
3. **Update GitHub Project**: Move UI implementation issue to "Done" if verification passed
4. **Create follow-up issues**: For any problems found
5. **Comment on PR**: Add verification results to the PR that implemented the UI
6. **Update PROMPT.md**: Check off UI verification task if complete

---

## Notes

### Element Reference Format

Playwright snapshots return element references in this format:

```
[ref="elementId-or-selector"]
```

When using `browser_click`, `browser_type`, etc., copy the exact ref string from the snapshot output.

### Adaptive Testing

The command sequences above use placeholders like `[REF_FROM_SNAPSHOT]`. During actual execution:

1. Run `browser_snapshot` first
2. Review output to find element refs
3. Copy exact ref string
4. Use in subsequent commands

### Screenshot Storage

Screenshots are saved to the Playwright MCP server's storage. File paths:

- `crystalshards-homepage-desktop.png`
- `crystalshards-homepage-mobile.png`
- `crystalshards-browse-desktop.png`
- etc.

### Data Requirements

For comprehensive testing, the database should contain:

- **At least 30 shards** (for pagination testing)
- **Shards with various licenses** (MIT, Apache, BSD, GPL)
- **Shards with varying star counts** (0, 10+, 50+, 100+, 500+)
- **Shards with and without documentation**
- **Shards with dependencies** (runtime and dev)
- **Shards with multiple versions**

If test data is insufficient, note in verification results.

### Browser State

Playwright maintains browser state between commands. To reset:

```bash
mcp__playwright__browser_close
# Then navigate to start fresh
```

### Parallel Testing

If multiple agents are verifying different apps simultaneously:

- Each agent should use separate browser instances
- Coordinate to avoid resource contention
- Document which pages each agent is testing

---

## Appendix: Playwright MCP Tool Reference

### Navigation

- `browser_navigate --url "https://..."` - Navigate to URL
- `browser_navigate_back` - Go back
- `browser_resize --width X --height Y` - Change viewport

### Inspection

- `browser_snapshot` - Capture accessibility tree (PREFERRED)
- `browser_take_screenshot --filename "..." [--fullPage]` - Visual screenshot
- `browser_console_messages [--onlyErrors]` - Get console logs
- `browser_network_requests` - Get network traffic

### Interaction

- `browser_click --element "description" --ref "[ref]"` - Click element
- `browser_type --element "description" --ref "[ref]" --text "..."` - Type text
- `browser_fill_form --fields '[...]'` - Fill multiple fields
- `browser_select_option --element "description" --ref "[ref]" --values '["..."]'` - Select dropdown
- `browser_press_key --key "Enter"` - Press keyboard key
- `browser_hover --element "description" --ref "[ref]"` - Hover over element

### Advanced

- `browser_evaluate --function "()" => { ... }"` - Run JavaScript
- `browser_wait_for --text "..." [--textGone "..."] [--time N]` - Wait for condition
- `browser_tabs --action list|new|close|select [--index N]` - Manage tabs

### Cleanup

- `browser_close` - Close browser

---

## End of Verification Plan

This plan is ready for execution once CrystalShards deployment completes. Update this document with actual execution results and findings.
