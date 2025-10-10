# CrystalShards UI/UX Verification Documentation

**Status**: READY TO EXECUTE (awaiting deployment completion)

**Purpose**: Comprehensive Playwright MCP verification of CrystalShards.org UI as required by CLAUDE.md Section 12.

---

## Quick Start

**Is deployment ready?**

```bash
curl -I https://crystalshards.org
# Should return: HTTP 200 OK
```

**Ready to verify?**

1. Read **Quick Reference** for 5-minute smoke test
2. Execute smoke test
3. If passed → Follow **Execution Order** below
4. Document results using **Results Template**
5. Create GitHub issues for any problems

---

## Documentation Structure

This directory contains everything needed for CrystalShards UI/UX verification:

| File | Purpose | When to Use |
|------|---------|-------------|
| **README.md** | This file - Overview and navigation | Start here |
| **quick-reference.md** | Essential commands and checklists | During verification |
| **crystalshards-playwright-verification-plan.md** | Comprehensive test plan with detailed scenarios | Planning and reference |
| **verification-checklist.md** | Printable checklist for tracking progress | During verification |
| **results-template.md** | Template for documenting results | After verification |
| **execute-verification.sh** | Guided execution script | Interactive verification |

---

## Verification Overview

### What We're Testing

**Three Core Pages:**
1. **Homepage** (`/`) - Hero, search, featured shards, stats
2. **Browse/Search** (`/shards`) - Search, filters, sorting, pagination
3. **Package Detail** (`/shards/:name`) - Package info, installation, README, dependencies

**Six Quality Dimensions:**
1. **Visual & Layout** - No broken layouts, consistent spacing
2. **Navigation & Usability** - Links work, intuitive flow
3. **Interactive Elements** - Buttons, forms, filters function correctly
4. **Accessibility** - Keyboard navigation, semantic HTML, ARIA labels
5. **Performance** - Load times < 2s, no blocking resources
6. **Content** - Real data, proper formatting, no placeholders

**Three Viewport Sizes:**
- Mobile: 375×667 (iPhone SE)
- Tablet: 768×1024 (iPad)
- Desktop: 1920×1080 (Full HD)

### Why We're Testing

**CLAUDE.md Section 12 requires UI/UX verification for all user-facing changes.**

This ensures:
- Deployed apps are human-readable and accessible
- Visual bugs are caught before users see them
- Accessibility standards are met
- Performance is acceptable
- Business logic works end-to-end

### Success Criteria

**PASS**: All critical criteria met, zero critical issues
**PASS WITH ISSUES**: Critical criteria met, some high/medium issues (documented)
**FAIL**: Critical criteria not met or critical issues found

**Critical Criteria (Must All Pass):**
- All pages load without errors
- Zero console errors
- Core functionality works (search, filters, navigation)
- Responsive design works (mobile, tablet, desktop)
- No broken layouts
- Semantic HTML structure

---

## Execution Order

**Total Estimated Time: 60-90 minutes**

### Phase 1: Smoke Test (5 minutes)

**Purpose**: Quick sanity check before detailed verification

**Steps**:
1. Navigate to homepage, browse, package detail
2. Capture snapshots
3. Check console errors
4. Verify pages load

**Decision Point**:
- ✅ All pages load, zero errors → Proceed to Phase 2
- ❌ Critical errors → STOP, create issues, wait for fix

### Phase 2: Homepage Verification (15 minutes)

**Purpose**: Comprehensive homepage testing

**Steps**:
1. Verify hero section, search, stats
2. Test search functionality
3. Test "View All Shards" link
4. Check featured and recent shards grids
5. Test responsive design (mobile, tablet, desktop)
6. Check console and network

### Phase 3: Browse/Search Verification (20 minutes)

**Purpose**: Test search, filters, sorting, pagination

**Steps**:
1. Test search input and submission
2. Test all filter controls (sort, license, stars, docs)
3. Test "Apply Filters" and "Clear Filters"
4. Test pagination (if > 20 shards)
5. Test empty state (no results)
6. Test responsive design

### Phase 4: Package Detail Verification (15 minutes)

**Purpose**: Test package detail page sections

**Steps**:
1. Verify header (title, version, description, stats)
2. Verify installation section (code blocks)
3. Verify README section
4. Verify dependencies section
5. Verify sidebar (links, versions, metadata)
6. Test external links (target="_blank")
7. Test dependency links
8. Test responsive design

### Phase 5: Cross-Page Navigation (10 minutes)

**Purpose**: Verify navigation flow between pages

**Steps**:
1. Test header navigation (Home, Browse, Docs)
2. Test logo link to homepage
3. Test search navigation (homepage → browse)
4. Test shard card links (browse → detail)
5. Test dependency links (detail → detail)
6. Test browser back button

### Phase 6: Accessibility (10 minutes)

**Purpose**: Verify keyboard navigation and accessibility

**Steps**:
1. Tab through all pages
2. Verify focus indicators
3. Test Enter/Space activation
4. Check heading hierarchy
5. Check ARIA labels
6. Check alt text on images

### Phase 7: Performance (10 minutes)

**Purpose**: Measure load times and identify bottlenecks

**Steps**:
1. Measure homepage load time
2. Measure browse page load time
3. Measure package detail load time
4. Analyze network requests
5. Identify slow resources

### Phase 8: Documentation (15 minutes)

**Purpose**: Create summary and issues

**Steps**:
1. Fill out results template
2. Create GitHub issues for all problems
3. Comment on implementation PR/issues
4. Update GitHub Project status
5. Close browser

---

## How to Use This Documentation

### For First-Time Verification

1. **Read**: `README.md` (this file) - Overview
2. **Reference**: `quick-reference.md` - Keep open during verification
3. **Follow**: `crystalshards-playwright-verification-plan.md` - Detailed test scenarios
4. **Track**: `verification-checklist.md` - Check off items as you go
5. **Document**: `results-template.md` - Fill in after completion

### For Quick Spot-Check

1. **Run**: 5-minute smoke test from `quick-reference.md`
2. **Check**: Critical items from `verification-checklist.md`
3. **Document**: Brief summary in results template

### For Comprehensive Verification

1. **Follow**: All phases in execution order above
2. **Reference**: Detailed scenarios in `crystalshards-playwright-verification-plan.md`
3. **Track**: All items in `verification-checklist.md`
4. **Document**: Complete results template with all findings

### For Interactive Execution

1. **Run**: `bash execute-verification.sh`
2. **Follow**: Interactive prompts
3. **Copy/paste**: Playwright commands shown
4. **Document**: Results as you go

---

## Prerequisites

**Before starting verification:**

- [x] CrystalShards deployment complete and accessible
- [x] Playwright MCP server running
- [x] Browser installed (`mcp__playwright__browser_install`)
- [x] GitHub CLI authenticated (`gh auth status`)
- [x] Database seeded with test data
- [x] Results directory exists (`mkdir -p results/`)

**Test Data Requirements:**

For comprehensive testing, database should contain:
- At least 30 shards (for pagination)
- Shards with various licenses (MIT, Apache, BSD, GPL)
- Shards with varying star counts (0, 10+, 50+, 100+, 500+)
- Shards with and without documentation
- Shards with dependencies (runtime and dev)
- Shards with multiple versions

**If test data insufficient**: Note in verification results, mark certain tests as N/A.

---

## Playwright MCP Quick Reference

### Core Workflow

```bash
# 1. Navigate
mcp__playwright__browser_navigate --url "https://crystalshards.org"

# 2. Snapshot (ALWAYS FIRST)
mcp__playwright__browser_snapshot

# 3. Check errors
mcp__playwright__browser_console_messages --onlyErrors true

# 4. Interact (using refs from snapshot)
mcp__playwright__browser_type \
  --element "search input" \
  --ref "[REF_FROM_SNAPSHOT]" \
  --text "query"

mcp__playwright__browser_click \
  --element "button" \
  --ref "[REF_FROM_SNAPSHOT]"

# 5. Verify result
mcp__playwright__browser_snapshot

# 6. Screenshot (if visual needed)
mcp__playwright__browser_take_screenshot --filename "name.png"
```

### Key Principles

- **Snapshot first** - Always run `browser_snapshot` before interaction
- **Copy exact refs** - Element refs from snapshot must be exact
- **Check errors always** - Run `console_messages` on every page
- **Screenshot sparingly** - Use snapshots unless visual verification needed
- **Test responsive** - Resize browser for mobile/tablet/desktop
- **Document issues** - Create GitHub issues for all problems

---

## Issue Reporting

**When issues found:**

1. **Take screenshot**: `browser_take_screenshot --filename "issue-X.png"`
2. **Capture snapshot**: `browser_snapshot` (save output)
3. **Save console errors**: `browser_console_messages` (save output)
4. **Create GitHub issue**: Use templates from verification plan
5. **Link to verification**: Reference this verification run

**Issue Templates Available:**
- UI Bug Template
- Accessibility Issue Template
- Performance Issue Template

All templates in `crystalshards-playwright-verification-plan.md`

---

## Results and Deliverables

**After verification, produce:**

1. **Completed Results Document**
   - Use `results-template.md`
   - Fill all sections
   - Include screenshots
   - List all issues found

2. **GitHub Issues**
   - One issue per problem
   - Use appropriate template
   - Include screenshots/logs
   - Tag with labels: `bug,ui,crystalshards`

3. **Summary Comment**
   - Add to implementation PR/issue
   - Include pass/fail status
   - Link to results document
   - List critical issues (if any)

4. **Updated GitHub Project**
   - Move UI implementation to "Done" (if passed)
   - Update status of related issues
   - Close issues if all verified

---

## Troubleshooting

**Problem**: Deployment not accessible

```bash
# Check deployment status
curl -I https://crystalshards.org

# Check Kubernetes pods
kubectl get pods -n crystalshards

# Check deployment logs
kubectl logs -n crystalshards deployment/crystalshards --tail=100
```

**Problem**: Browser not installed

```bash
mcp__playwright__browser_install
```

**Problem**: Element ref not found

- Review snapshot output carefully
- Element refs are in format: `[ref="..."]`
- Copy exact ref string from snapshot
- Don't guess or approximate

**Problem**: Page timeout

- Increase wait time or check if deployment is responding
- May indicate deployment issue, not UI issue

**Problem**: Too many issues found

- Prioritize critical and high priority
- Create GitHub issues for all, but focus fixes on critical
- May indicate deployment not ready for verification

---

## Success Tips

**For efficient verification:**

1. **Follow the plan** - Don't skip steps, they build on each other
2. **Snapshot everything** - Snapshots are fast and informative
3. **Check errors early** - Console errors indicate problems
4. **Test mobile first** - Mobile often reveals layout issues
5. **Document as you go** - Don't wait until end
6. **Create issues promptly** - While issue is fresh in mind
7. **Take breaks** - 90 minutes is long, break into phases

**For thorough verification:**

1. **Read page source** - Understand what's being tested
2. **Test edge cases** - Empty states, long text, special chars
3. **Verify assumptions** - Don't assume, verify
4. **Check all viewports** - Responsive issues are common
5. **Test keyboard nav** - Accessibility is critical
6. **Measure performance** - Load times matter

---

## After Verification

**Next steps:**

1. **If PASS**:
   - Comment on implementation issue/PR with ✅ results
   - Update GitHub Project to "Done"
   - Close related issues
   - Celebrate! 🎉

2. **If PASS WITH ISSUES**:
   - Create GitHub issues for all problems (use templates)
   - Prioritize issues (critical → high → medium → low)
   - Comment on implementation issue/PR with results + issue links
   - Decide: Launch with known issues or fix first?
   - Update GitHub Project based on decision

3. **If FAIL**:
   - Create CRITICAL GitHub issue describing failure
   - Comment on implementation issue/PR with ❌ results
   - DO NOT launch until critical issues fixed
   - Re-run verification after fixes
   - Keep GitHub Project in "In Progress" or "In Review"

---

## Related Documentation

- **CLAUDE.md Section 12**: UI/UX Verification Requirements
- **GitHub Project #1**: CrystalShards.org Development
- **Implementation PRs**:
  - Homepage UI: #45
  - Browse/Search UI: #34
  - Package Detail UI: #47

---

## Contact and Support

**Questions?**
- Reference CLAUDE.md Section 12 for requirements
- Check Playwright MCP documentation
- Review verification plan for detailed scenarios

**Issues with verification process?**
- Create issue in GitHub Project #5 (Agent Enhancements)
- Tag with `verification,tooling`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-10-10 | Initial comprehensive verification plan created |

---

## License

Part of CrystalShards monorepo. Internal documentation for development use.

---

**Ready to verify? Start with the smoke test in `quick-reference.md`!**
