# CrystalShards UI Verification - Quick Reference

## Pre-Flight Check

```bash
# 1. Check deployment
curl -I https://crystalshards.org

# 2. Install browser (if needed)
# mcp__playwright__browser_install

# 3. Start verification
```

## 5-Minute Smoke Test

```bash
# Homepage
mcp__playwright__browser_navigate --url "https://crystalshards.org"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

# Browse
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true

# Detail
mcp__playwright__browser_navigate --url "https://crystalshards.org/shards/[SHARD_NAME]"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages --onlyErrors true
```

**If smoke test passes → Proceed to full verification**
**If smoke test fails → STOP, create critical issues, fix deployment**

## Essential Playwright Commands

### Navigation
```bash
mcp__playwright__browser_navigate --url "https://..."
mcp__playwright__browser_navigate_back
```

### Inspection (Always start with snapshot!)
```bash
mcp__playwright__browser_snapshot  # PREFERRED - Fast, semantic
mcp__playwright__browser_take_screenshot --filename "name.png"  # Visual only
mcp__playwright__browser_console_messages --onlyErrors true  # Check errors
mcp__playwright__browser_network_requests  # Network traffic
```

### Interaction (Get refs from snapshot first!)
```bash
mcp__playwright__browser_type \
  --element "search input" \
  --ref "[REF_FROM_SNAPSHOT]" \
  --text "search query"

mcp__playwright__browser_click \
  --element "button description" \
  --ref "[REF_FROM_SNAPSHOT]"

mcp__playwright__browser_select_option \
  --element "dropdown description" \
  --ref "[REF_FROM_SNAPSHOT]" \
  --values '["option_value"]'

mcp__playwright__browser_press_key --key "Enter"
```

### Responsive Testing
```bash
# Mobile
mcp__playwright__browser_resize --width 375 --height 667

# Tablet
mcp__playwright__browser_resize --width 768 --height 1024

# Desktop
mcp__playwright__browser_resize --width 1920 --height 1080
```

### Advanced
```bash
# Run JavaScript
mcp__playwright__browser_evaluate --function "() => { return document.title; }"

# Wait for content
mcp__playwright__browser_wait_for --text "Search results"

# Close browser
mcp__playwright__browser_close
```

## Critical Checks (Must All Pass)

- [ ] All pages load (200 OK)
- [ ] Zero console errors
- [ ] Search works (redirects to /shards?query=...)
- [ ] Filters work (URL updates)
- [ ] Navigation works (header links)
- [ ] Mobile responsive (no horizontal scroll)

## Issue Creation (If Problems Found)

```bash
gh issue create \
  --title "UI Issue: [brief description]" \
  --label "bug,ui,crystalshards" \
  --body "$(cat <<'EOF'
## Description
[What's wrong]

## Page
[URL where issue occurs]

## Steps to Reproduce
1. Navigate to [URL]
2. [Action]
3. [Observe issue]

## Expected
[What should happen]

## Actual
[What actually happens]

## Screenshot
[Attach screenshot]

## Severity
- [ ] Critical
- [ ] High
- [ ] Medium
- [ ] Low

Discovered during Playwright verification (CLAUDE.md Section 12)
EOF
)"
```

## Pages to Test

| Page | URL | Key Elements |
|------|-----|--------------|
| Homepage | `/` | Hero, search, featured, recent, stats |
| Browse | `/shards` | Search, filters, sort, pagination, results |
| Detail | `/shards/:name` | Header, installation, README, deps, sidebar |

## Viewports to Test

| Device | Width × Height | Layout |
|--------|----------------|--------|
| Mobile | 375 × 667 | Single column, stacked |
| Tablet | 768 × 1024 | 2 columns, may wrap |
| Desktop | 1920 × 1080 | 3-4 columns, max-width |

## Success Criteria

**PASS** = All critical checks pass, zero critical issues
**PASS WITH ISSUES** = Critical checks pass, some high/medium issues
**FAIL** = Critical checks fail or critical issues found

## Full Documentation

- **Detailed Plan**: `/workspaces/monorepo/.agent/ui-verification/crystalshards-playwright-verification-plan.md`
- **Checklist**: `/workspaces/monorepo/.agent/ui-verification/verification-checklist.md`
- **Results Template**: `/workspaces/monorepo/.agent/ui-verification/results-template.md`
- **Execution Script**: `/workspaces/monorepo/.agent/ui-verification/execute-verification.sh`

## Quick Wins

**If time limited, prioritize:**
1. Smoke test (5 min)
2. Homepage search (5 min)
3. Browse filters (10 min)
4. Mobile responsive check (10 min)
5. Console error check (2 min)

**Total: 32 minutes for basic verification**

## Common Issues to Watch For

- Horizontal scrolling on mobile
- Console errors (JavaScript exceptions)
- 404/500 network errors
- Broken links (404 pages)
- Filters not updating URL
- Pagination not working
- Search not redirecting
- External links missing target="_blank"
- Missing alt text on images
- Poor color contrast
- No focus indicators
- Overlapping elements

## After Verification

1. **Create summary** using results template
2. **Create GitHub issues** for all problems found
3. **Comment on implementation PR/issues** with results
4. **Update GitHub Project** status to Done (if passed)
5. **Close browser**: `mcp__playwright__browser_close`

## Emergency: Deployment Broken

If smoke test reveals critical deployment issues:

1. **STOP verification immediately**
2. **Create CRITICAL GitHub issue** with deployment error details
3. **Comment on deployment issue/PR** with error logs
4. **Do NOT proceed with full verification** until fixed
5. **Document error in results** with timestamp

## Tips

- **Always snapshot first** - Get element refs before interaction
- **Copy exact refs** - Don't guess, copy from snapshot output
- **Check console on every page** - Errors indicate problems
- **Screenshot sparingly** - Use snapshots unless visual needed
- **Document everything** - Screenshots + issue descriptions
- **Test happy path first** - Then edge cases
- **Mobile is critical** - Many users on mobile

## Workflow

```
1. Smoke Test (5 min)
   ↓ PASS
2. Homepage Full (15 min)
   ↓ PASS
3. Browse Full (20 min)
   ↓ PASS
4. Detail Full (15 min)
   ↓ PASS
5. Responsive Check (10 min)
   ↓ PASS
6. Accessibility Check (10 min)
   ↓ PASS
7. Create Summary
8. Create Issues
9. Update GitHub
10. Done ✓
```

**Total Time: 60-90 minutes for comprehensive verification**

---

**When in doubt, refer to the full plan document!**
