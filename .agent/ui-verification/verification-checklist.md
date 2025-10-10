# CrystalShards UI/UX Verification Checklist

**Target**: https://crystalshards.org
**Date**: _____________
**Verifier**: _____________
**Status**: [ ] PASS [ ] PASS WITH ISSUES [ ] FAIL

---

## Pre-Flight Checks

- [ ] Deployment is live and accessible
- [ ] Playwright MCP browser installed
- [ ] GitHub CLI authenticated
- [ ] Database seeded with test data
- [ ] Results directory created

---

## Smoke Test (CRITICAL)

- [ ] Homepage loads without errors
- [ ] Browse page loads without errors
- [ ] Package detail page loads without errors
- [ ] Zero console errors on all pages
- [ ] Zero 500 errors in network requests
- [ ] Zero 404 errors for critical resources

**If smoke test fails, STOP and fix critical issues before proceeding.**

---

## Homepage Verification

### Layout & Visual
- [ ] Hero section displays correctly
- [ ] Hero title: "CrystalShards"
- [ ] Hero subtitle displays
- [ ] Search bar visible and properly styled
- [ ] Stats display (total shards, downloads)
- [ ] Numbers formatted with commas (1,234,567)
- [ ] Featured shards grid displays
- [ ] Recently updated shards grid displays
- [ ] "View All Shards →" link visible
- [ ] No overlapping elements
- [ ] No content overflow
- [ ] Consistent spacing throughout

### Functionality
- [ ] Search input accepts text
- [ ] Search button submits form
- [ ] Search redirects to /shards?query=...
- [ ] Shard cards link to detail pages (/shards/:name)
- [ ] "View All Shards" link navigates to /shards
- [ ] Header navigation links work

### Responsive Design
- [ ] Mobile (375×667): No horizontal scroll
- [ ] Mobile: Search bar full width
- [ ] Mobile: Shard grid single column
- [ ] Mobile: Stats stack vertically
- [ ] Tablet (768×1024): Grid shows 2 columns
- [ ] Tablet: Layout adapts appropriately
- [ ] Desktop (1920×1080): Grid shows 3-4 columns
- [ ] Desktop: Content max-width applied

### Accessibility
- [ ] Heading hierarchy: h1 (CrystalShards) → h2 (Featured/Recent)
- [ ] Search input has label or aria-label
- [ ] Focus indicators visible on interactive elements
- [ ] Tab order is logical
- [ ] Enter activates search button

### Performance
- [ ] Page loads in < 2 seconds
- [ ] No blocking resources
- [ ] No long-running scripts

### Content
- [ ] No placeholder/lorem ipsum text
- [ ] Stats show real numbers (or 0 if empty)
- [ ] Shard cards show real data

---

## Browse/Search Page Verification

### Layout & Visual
- [ ] Page header displays correctly
- [ ] Page title: "Browse Shards" or "Search: {query}"
- [ ] Search results count visible (if search)
- [ ] Search bar visible and populated with query
- [ ] Filters section displays
- [ ] Filter controls aligned properly
- [ ] Shard list or empty state displays
- [ ] Pagination displays (if > 20 results)
- [ ] No overlapping elements
- [ ] Consistent spacing

### Search Functionality
- [ ] Search input preserves query from URL
- [ ] Search submits to /shards?query=...
- [ ] Results filtered by query
- [ ] Search results count accurate
- [ ] Empty state displays if no results
- [ ] Empty state message: "No shards found matching your search."
- [ ] "View All Shards" button in empty state

### Filters & Sorting
- [ ] Sort dropdown displays
- [ ] Sort options: Recently Updated, Most Popular, Most Downloads, Name A-Z
- [ ] Sort default: Recently Updated
- [ ] License filter displays
- [ ] License options: All, MIT, Apache-2.0, BSD-3-Clause, GPL-3.0
- [ ] Min Stars filter displays
- [ ] Min Stars options: Any, 10+, 50+, 100+, 500+
- [ ] Has Docs checkbox displays
- [ ] Apply Filters button submits form
- [ ] Clear Filters button appears when filters active
- [ ] Filters update URL params correctly
- [ ] Clear Filters resets to base URL (or query only)
- [ ] Results update after applying filters

### Pagination
- [ ] Pagination displays if total_pages > 1
- [ ] Page info displays: "Page X of Y"
- [ ] "Next →" link visible on page 1
- [ ] "← Previous" link visible on page 2+
- [ ] Next/Previous links navigate correctly
- [ ] URL updates with page param
- [ ] Results update for each page

### Responsive Design
- [ ] Mobile (375×667): Filters stack vertically
- [ ] Mobile: Dropdowns full width
- [ ] Mobile: Shard list single column
- [ ] Mobile: Pagination stacks vertically
- [ ] Tablet (768×1024): Filters may wrap
- [ ] Tablet: Shard list 2 columns
- [ ] Desktop (1920×1080): Filters inline
- [ ] Desktop: Shard list 3-4 columns

### Accessibility
- [ ] Heading hierarchy: h1 (Browse/Search) → card titles
- [ ] Form labels present (Sort by, License, Min Stars)
- [ ] Dropdowns have labels
- [ ] Checkbox has label
- [ ] Focus indicators visible
- [ ] Tab order logical
- [ ] Dropdowns accessible via keyboard
- [ ] Space toggles checkbox

### Performance
- [ ] Page loads in < 2 seconds
- [ ] Filter changes load quickly
- [ ] Pagination loads quickly

### Content
- [ ] No placeholder text
- [ ] Shard cards show real data
- [ ] Counts accurate

---

## Package Detail Page Verification

### Layout & Visual
- [ ] Header section displays
- [ ] Shard title (h1) displays
- [ ] Version badge displays (v1.2.3 format)
- [ ] Description displays (if exists)
- [ ] Stats block displays (stars, downloads, license)
- [ ] GitHub stars formatted (⭐ count)
- [ ] Two-column layout (main + sidebar)
- [ ] Installation section displays
- [ ] README section displays
- [ ] Dependencies section displays (if any)
- [ ] Documentation section displays (if docs_url)
- [ ] Sidebar links section displays
- [ ] Sidebar versions section displays
- [ ] Sidebar provider section displays
- [ ] Sidebar metadata section displays
- [ ] No overlapping elements
- [ ] Consistent spacing

### Installation Section
- [ ] "Installation" heading (h2)
- [ ] Code block: shard.yml snippet
- [ ] Code block: shards install command
- [ ] Code blocks properly formatted
- [ ] Syntax highlighting (if applicable)
- [ ] shard.yml shows correct format:
  - dependencies:
  - {name}:
  - github: {path}
  - version: ~> {version}

### README Section
- [ ] "README" heading (h2)
- [ ] README content displays
- [ ] Links work
- [ ] Fallback text if no README

### Dependencies Section
- [ ] "Dependencies" heading (h2)
- [ ] Runtime dependencies labeled
- [ ] Development dependencies labeled
- [ ] Dependencies listed with names
- [ ] Version requirements shown
- [ ] Dev dependencies have badge
- [ ] Dependency names link to shard detail pages
- [ ] "No dependencies" message if none

### Sidebar - Links
- [ ] "Links" heading (h3)
- [ ] Repository link displays
- [ ] Homepage link displays (if exists)
- [ ] Documentation link displays (if exists)
- [ ] All external links have target="_blank"
- [ ] Links point to correct URLs

### Sidebar - Versions
- [ ] "Versions" heading (h3)
- [ ] Version list displays (up to 10)
- [ ] Version numbers shown
- [ ] Release dates shown
- [ ] Dates formatted: "Jan 1, 2025"
- [ ] Yanked versions styled differently
- [ ] Footer shows "and X more..." if > 10 versions

### Sidebar - Provider
- [ ] "Provider" heading (h3)
- [ ] Provider displays (capitalized)

### Sidebar - Metadata
- [ ] "Metadata" heading (h3)
- [ ] Created date displays
- [ ] Updated date displays
- [ ] Crystal version displays (if exists)
- [ ] Dates formatted correctly

### Functionality
- [ ] Repository link opens in new tab
- [ ] Homepage link opens in new tab (if exists)
- [ ] Documentation link opens in new tab (if exists)
- [ ] Dependency links navigate to other shards
- [ ] Back button works

### Responsive Design
- [ ] Mobile (375×667): Single column layout
- [ ] Mobile: Sidebar below main content
- [ ] Mobile: Installation code blocks scroll horizontally
- [ ] Mobile: Stats stack vertically
- [ ] Tablet (768×1024): Two-column or responsive
- [ ] Desktop (1920×1080): Optimal two-column

### Accessibility
- [ ] Heading hierarchy: h1 (name) → h2 (sections) → h3 (sidebar)
- [ ] Code blocks have semantic markup (pre/code)
- [ ] Links descriptive
- [ ] Focus indicators visible
- [ ] External links announced (target="_blank")

### Performance
- [ ] Page loads in < 2 seconds
- [ ] README renders quickly

### Content
- [ ] No placeholder text
- [ ] Real data displays
- [ ] Code blocks accurate
- [ ] Version badge matches latest

---

## Cross-Page Navigation

- [ ] Homepage → Browse (via header)
- [ ] Homepage → Browse (via "View All Shards")
- [ ] Browse → Homepage (via header)
- [ ] Browse → Homepage (via logo)
- [ ] Homepage → Detail (via shard card)
- [ ] Browse → Detail (via shard card)
- [ ] Detail → Detail (via dependency link)
- [ ] Detail → Browse (via back button)
- [ ] Search → Results (via search form)
- [ ] Header navigation consistent across pages
- [ ] Logo always links to homepage
- [ ] Active page highlighted in nav (if applicable)

---

## Accessibility Deep Dive

### Keyboard Navigation
- [ ] All pages: Tab through all interactive elements
- [ ] Tab order is logical (top-to-bottom, left-to-right)
- [ ] Focus indicators visible on all elements
- [ ] No keyboard traps
- [ ] Enter activates buttons
- [ ] Space activates checkboxes
- [ ] Arrow keys work in dropdowns (if applicable)
- [ ] Escape closes modals (if applicable)

### Semantic HTML
- [ ] Proper heading hierarchy (h1 → h2 → h3)
- [ ] Forms use <form> tags
- [ ] Inputs have <label> or aria-label
- [ ] Buttons use <button> tags
- [ ] Links use <a> tags
- [ ] Lists use <ul>/<ol> tags
- [ ] Nav uses <nav> tag
- [ ] Main content uses <main> tag (if applicable)

### ARIA Labels
- [ ] Interactive elements without text have aria-label
- [ ] Form inputs have aria-describedby for errors (if applicable)
- [ ] Status messages have aria-live (if applicable)
- [ ] Icon-only buttons have aria-label

### Images
- [ ] All images have alt attribute
- [ ] Decorative images have empty alt (alt="")
- [ ] Meaningful images have descriptive alt

### Color Contrast
- [ ] Text on background meets WCAG AA (4.5:1 for normal text)
- [ ] Links distinguishable from surrounding text
- [ ] Focus indicators have sufficient contrast

---

## Performance Deep Dive

### Load Times
- [ ] Homepage: _____ ms (target: < 2000ms)
- [ ] Browse: _____ ms (target: < 2000ms)
- [ ] Package Detail: _____ ms (target: < 2000ms)

### Metrics
- [ ] Time to First Byte (TTFB) < 500ms
- [ ] DOM Content Loaded < 1000ms
- [ ] All pages fully loaded < 2000ms

### Network
- [ ] No failed requests (404/500)
- [ ] No blocking resources
- [ ] Images optimized (if any)
- [ ] CSS/JS minified (in production)
- [ ] Lazy loading implemented (if applicable)

### Rendering
- [ ] No layout shifts
- [ ] No cumulative layout shift issues
- [ ] Smooth scrolling
- [ ] No janky animations

---

## Error Handling

### Console Errors
- [ ] Homepage: Zero console errors
- [ ] Browse: Zero console errors
- [ ] Package Detail: Zero console errors
- [ ] No uncaught exceptions
- [ ] No deprecation warnings

### Network Errors
- [ ] No 404 errors for critical resources
- [ ] No 500 server errors
- [ ] Optional resources gracefully handle 404

### Edge Cases
- [ ] Empty state displays correctly (no shards)
- [ ] Empty search results handled
- [ ] Missing optional fields handled (homepage_url, docs_url)
- [ ] No dependencies handled
- [ ] Single shard (no pagination) handled
- [ ] Long shard names handled
- [ ] Long descriptions handled
- [ ] Special characters in search handled

---

## Browser Compatibility

Note: Playwright tests Chromium by default. For comprehensive testing, also test:

- [ ] Firefox (manual or separate Playwright run)
- [ ] Safari (manual or separate Playwright run)
- [ ] Mobile browsers (iOS Safari, Chrome Android)

---

## Final Verification

### Critical Success Criteria (MUST PASS)
- [ ] All pages load without errors
- [ ] Zero console errors
- [ ] Core functionality works (search, filters, navigation)
- [ ] Responsive design works (mobile, tablet, desktop)
- [ ] No broken layouts
- [ ] Semantic HTML structure

### High Priority (SHOULD PASS)
- [ ] External links have target="_blank"
- [ ] Empty states handled
- [ ] Keyboard navigation works
- [ ] Focus indicators visible
- [ ] Pages load quickly (< 2s)
- [ ] Content formatted correctly

### Medium Priority (NICE TO HAVE)
- [ ] Hover states present
- [ ] ARIA labels comprehensive
- [ ] Color contrast meets WCAG AA
- [ ] All metadata displays

---

## Issues Summary

**Critical Issues** (blocks functionality):
1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

**High Priority Issues** (significant UX impact):
1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

**Medium Priority Issues** (minor cosmetic):
1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

**Total Issues Created**: _____

---

## Verification Results

**Overall Status**: [ ] PASS [ ] PASS WITH ISSUES [ ] FAIL

**Homepage**: [ ] PASS [ ] ISSUES [ ] FAIL
**Browse/Search**: [ ] PASS [ ] ISSUES [ ] FAIL
**Package Detail**: [ ] PASS [ ] ISSUES [ ] FAIL

**Recommendation**:
- [ ] Approve for production
- [ ] Fix critical issues before launch
- [ ] Fix high priority issues before launch
- [ ] Launch with known issues (documented)

---

## Sign-Off

**Verifier**: _____________
**Date**: _____________
**Signature**: _____________

**Notes**:
_____________________________________________________________
_____________________________________________________________
_____________________________________________________________
