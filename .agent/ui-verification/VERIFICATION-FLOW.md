# CrystalShards UI Verification Flow

Visual guide to the verification process.

---

## Pre-Flight Checks

```
┌─────────────────────────────────────┐
│  Is Deployment Ready?               │
│                                     │
│  ✓ https://crystalshards.org        │
│    returns 200 OK                   │
│                                     │
│  ✓ Playwright MCP browser           │
│    installed                        │
│                                     │
│  ✓ GitHub CLI authenticated         │
│                                     │
│  ✓ Database seeded with             │
│    test data                        │
└─────────────────────────────────────┘
         │
         ▼
    [ START ]
```

---

## Verification Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    PHASE 1: SMOKE TEST                        │
│                        (5 minutes)                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Navigate to Homepage                                     │
│     └─► mcp__playwright__browser_navigate                   │
│         --url "https://crystalshards.org"                   │
│                                                              │
│  2. Capture Snapshot                                         │
│     └─► mcp__playwright__browser_snapshot                   │
│                                                              │
│  3. Check Console Errors                                     │
│     └─► mcp__playwright__browser_console_messages           │
│         --onlyErrors true                                    │
│                                                              │
│  Repeat for:                                                 │
│  • /shards (Browse)                                          │
│  • /shards/[name] (Package Detail)                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
         │
         ├─► [ FAIL ] ──┐
         │              │
         ▼              ▼
    [ PASS ]     ┌──────────────────────┐
         │       │  STOP VERIFICATION   │
         │       │  Create CRITICAL     │
         │       │  GitHub Issue        │
         │       │  Wait for Fix        │
         │       └──────────────────────┘
         ▼

┌──────────────────────────────────────────────────────────────┐
│                   PHASE 2: HOMEPAGE                           │
│                      (15 minutes)                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Visual & Layout                                             │
│  ├─► Hero section displays                                   │
│  ├─► Search bar visible                                      │
│  ├─► Stats display (shards, downloads)                       │
│  ├─► Featured shards grid                                    │
│  └─► Recently updated grid                                   │
│                                                              │
│  Functionality                                               │
│  ├─► Search input accepts text                               │
│  ├─► Search redirects to /shards?query=...                   │
│  └─► "View All Shards" navigates to /shards                  │
│                                                              │
│  Responsive Design                                           │
│  ├─► Mobile (375×667)                                        │
│  ├─► Tablet (768×1024)                                       │
│  └─► Desktop (1920×1080)                                     │
│                                                              │
│  Performance                                                 │
│  └─► Load time < 2 seconds                                   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
         │
         ▼

┌──────────────────────────────────────────────────────────────┐
│                 PHASE 3: BROWSE/SEARCH                        │
│                      (20 minutes)                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Search Functionality                                        │
│  ├─► Search input preserves query                            │
│  ├─► Results filtered correctly                              │
│  └─► Empty state displays                                    │
│                                                              │
│  Filters                                                     │
│  ├─► Sort dropdown (updated, popular, downloads, name)       │
│  ├─► License filter (MIT, Apache, BSD, GPL)                  │
│  ├─► Min Stars (10+, 50+, 100+, 500+)                        │
│  └─► Has Docs checkbox                                       │
│                                                              │
│  Filter Actions                                              │
│  ├─► Apply Filters → URL updates                             │
│  └─► Clear Filters → Reset to base URL                       │
│                                                              │
│  Pagination                                                  │
│  ├─► Next/Previous links                                     │
│  ├─► Page info displays                                      │
│  └─► URL updates with page param                             │
│                                                              │
│  Responsive Design                                           │
│  ├─► Mobile: Filters stack vertically                        │
│  ├─► Tablet: Filters may wrap                                │
│  └─► Desktop: Filters inline                                 │
│                                                              │
└──────────────────────────────────────────────────────────────┘
         │
         ▼

┌──────────────────────────────────────────────────────────────┐
│                 PHASE 4: PACKAGE DETAIL                       │
│                      (15 minutes)                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Header Section                                              │
│  ├─► Shard title (h1)                                        │
│  ├─► Version badge (v1.2.3)                                  │
│  ├─► Description                                             │
│  └─► Stats (stars, downloads, license)                       │
│                                                              │
│  Main Content                                                │
│  ├─► Installation (code blocks)                              │
│  ├─► README section                                          │
│  ├─► Dependencies (runtime + dev)                            │
│  └─► Documentation link (if exists)                          │
│                                                              │
│  Sidebar                                                     │
│  ├─► Links (repository, homepage, docs)                      │
│  │   └─► All external links: target="_blank"                 │
│  ├─► Versions list (up to 10)                                │
│  ├─► Provider                                                │
│  └─► Metadata (created, updated, crystal version)            │
│                                                              │
│  Responsive Design                                           │
│  ├─► Mobile: Sidebar below main                              │
│  ├─► Tablet: Two-column or responsive                        │
│  └─► Desktop: Optimal two-column                             │
│                                                              │
└──────────────────────────────────────────────────────────────┘
         │
         ▼

┌──────────────────────────────────────────────────────────────┐
│                PHASE 5: CROSS-PAGE NAVIGATION                 │
│                      (10 minutes)                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Navigation Paths                                            │
│                                                              │
│  Homepage                                                    │
│    ├─► Header "Browse Shards" → /shards                      │
│    ├─► Search → /shards?query=...                            │
│    ├─► Shard Card → /shards/:name                            │
│    └─► "View All Shards" → /shards                           │
│                                                              │
│  Browse                                                      │
│    ├─► Header "Home" → /                                     │
│    ├─► Logo → /                                              │
│    └─► Shard Card → /shards/:name                            │
│                                                              │
│  Package Detail                                              │
│    ├─► Header "Home" → /                                     │
│    ├─► Header "Browse Shards" → /shards                      │
│    ├─► Dependency Link → /shards/:other-name                 │
│    └─► Browser Back → Previous page                          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
         │
         ▼

┌──────────────────────────────────────────────────────────────┐
│                   PHASE 6: ACCESSIBILITY                      │
│                      (10 minutes)                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Keyboard Navigation                                         │
│  ├─► Tab through all interactive elements                    │
│  ├─► Focus indicators visible                                │
│  ├─► Enter activates buttons                                 │
│  ├─► Space toggles checkboxes                                │
│  └─► No keyboard traps                                       │
│                                                              │
│  Semantic HTML                                               │
│  ├─► Heading hierarchy (h1 → h2 → h3)                        │
│  ├─► Forms use <form> tags                                   │
│  ├─► Inputs have <label> or aria-label                       │
│  └─► Proper landmark elements                                │
│                                                              │
│  ARIA & Alt Text                                             │
│  ├─► Interactive elements labeled                            │
│  ├─► Images have alt attributes                              │
│  └─► Status messages announced                               │
│                                                              │
│  Color Contrast                                              │
│  └─► WCAG AA compliance (4.5:1)                              │
│                                                              │
└──────────────────────────────────────────────────────────────┘
         │
         ▼

┌──────────────────────────────────────────────────────────────┐
│                    PHASE 7: PERFORMANCE                       │
│                      (10 minutes)                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Load Time Measurements                                      │
│  ├─► Homepage: < 2000ms                                      │
│  ├─► Browse: < 2000ms                                        │
│  └─► Package Detail: < 2000ms                                │
│                                                              │
│  Metrics                                                     │
│  ├─► Time to First Byte (TTFB)                               │
│  ├─► DOM Content Loaded                                      │
│  └─► Fully Loaded                                            │
│                                                              │
│  Network Analysis                                            │
│  ├─► Check for blocking resources                            │
│  ├─► Identify slow requests (> 1s)                           │
│  └─► Verify no 404/500 errors                                │
│                                                              │
└──────────────────────────────────────────────────────────────┘
         │
         ▼

┌──────────────────────────────────────────────────────────────┐
│                  PHASE 8: DOCUMENTATION                       │
│                      (15 minutes)                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Fill Results Template                                    │
│     └─► Use results-template.md                              │
│         • Executive summary                                  │
│         • Page-by-page results                               │
│         • Issues discovered                                  │
│         • Recommendations                                    │
│                                                              │
│  2. Create GitHub Issues                                     │
│     └─► For each problem found                               │
│         • Use appropriate template                           │
│         • Include screenshots                                │
│         • Tag: bug,ui,crystalshards                          │
│                                                              │
│  3. Comment on Implementation PR/Issues                      │
│     └─► Add verification summary                             │
│         • Pass/fail status                                   │
│         • Link to results document                           │
│         • List critical issues                               │
│                                                              │
│  4. Update GitHub Project                                    │
│     └─► Move to "Done" if passed                             │
│         • Update issue statuses                              │
│         • Close related issues                               │
│                                                              │
└──────────────────────────────────────────────────────────────┘
         │
         ▼

    ┌─────────┐
    │  DONE   │
    └─────────┘
```

---

## Decision Points

```
                ┌─────────────────────┐
                │   Smoke Test Pass?  │
                └─────────────────────┘
                     │          │
                     │          │
                   PASS       FAIL
                     │          │
                     ▼          ▼
              ┌──────────┐  ┌────────────────┐
              │ Continue │  │ STOP - Fix     │
              │ to Phase │  │ Critical       │
              │ 2-7      │  │ Issues First   │
              └──────────┘  └────────────────┘
                     │
                     ▼
                ┌─────────────────────┐
                │ All Critical Pass?  │
                └─────────────────────┘
                     │          │
                     │          │
                   PASS       FAIL
                     │          │
                     ▼          ▼
              ┌──────────┐  ┌────────────────┐
              │ Document │  │ Create         │
              │ Results  │  │ CRITICAL       │
              │          │  │ Issues         │
              └──────────┘  └────────────────┘
                     │          │
                     ▼          ▼
                ┌─────────────────────┐
                │ High Priority Pass? │
                └─────────────────────┘
                     │          │
                     │          │
                   PASS       FAIL
                     │          │
                     ▼          ▼
              ┌──────────┐  ┌────────────────┐
              │  PASS    │  │ PASS WITH      │
              │          │  │ ISSUES         │
              └──────────┘  └────────────────┘
                     │          │
                     │          │
                     └──────┬───┘
                            │
                            ▼
                ┌─────────────────────┐
                │ Update GitHub       │
                │ Project to "Done"   │
                └─────────────────────┘
```

---

## Parallel Workflow (All Pages)

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Homepage   │  │   Browse    │  │   Detail    │
│      /      │  │   /shards   │  │/shards/:name│
└─────────────┘  └─────────────┘  └─────────────┘
      │                │                │
      ▼                ▼                ▼
┌──────────────────────────────────────────────┐
│         For Each Page, Verify:               │
├──────────────────────────────────────────────┤
│  1. Navigate to page                         │
│  2. Capture snapshot                         │
│  3. Check console errors                     │
│  4. Check network requests                   │
│  5. Screenshot (desktop)                     │
│  6. Test interactions                        │
│  7. Resize to mobile (375×667)               │
│  8. Screenshot (mobile)                      │
│  9. Resize to tablet (768×1024)              │
│ 10. Screenshot (tablet)                      │
│ 11. Reset to desktop (1920×1080)             │
│ 12. Document findings                        │
└──────────────────────────────────────────────┘
```

---

## Responsive Testing Pattern

```
Desktop (1920×1080)
┌────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────┐  │
│  │         Max-width Container              │  │
│  │  ┌────────────────────────────────────┐  │  │
│  │  │  Header: Logo | Nav Links          │  │  │
│  │  ├────────────────────────────────────┤  │  │
│  │  │  Hero: Title | Search | Stats      │  │  │
│  │  ├────────────────────────────────────┤  │  │
│  │  │  Grid: [Card] [Card] [Card] [Card] │  │  │
│  │  └────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘

         ▼ Resize ▼

Tablet (768×1024)
┌──────────────────────────┐
│  Header: Logo | Nav      │
├──────────────────────────┤
│  Hero: Title             │
│        Search            │
│        Stats             │
├──────────────────────────┤
│  Grid: [Card]  [Card]    │
│        [Card]  [Card]    │
└──────────────────────────┘

         ▼ Resize ▼

Mobile (375×667)
┌───────────────┐
│ Header: Logo  │
│         Menu  │
├───────────────┤
│ Hero: Title   │
│       Search  │
│       Stats   │
├───────────────┤
│ Grid: [Card]  │
│       [Card]  │
│       [Card]  │
└───────────────┘

    ✓ No horizontal scroll
    ✓ Touch targets ≥ 44×44px
    ✓ All elements accessible
```

---

## Issue Severity Matrix

```
┌─────────────────────────────────────────────────────────┐
│                   ISSUE SEVERITY                        │
├────────────┬────────────────────────────────────────────┤
│ CRITICAL   │ • Blocks core functionality                │
│            │ • Prevents access to features              │
│            │ • Console errors breaking page             │
│            │ • 500 server errors                        │
│            │ • Search doesn't work                      │
│            │ • Filters broken                           │
│            │ → MUST FIX BEFORE LAUNCH                   │
├────────────┼────────────────────────────────────────────┤
│ HIGH       │ • Significant UX impact                    │
│            │ • Accessibility barriers                   │
│            │ • Broken layouts on mobile                 │
│            │ • Missing external link targets            │
│            │ • Poor performance (> 5s load)             │
│            │ → SHOULD FIX BEFORE LAUNCH                 │
├────────────┼────────────────────────────────────────────┤
│ MEDIUM     │ • Minor cosmetic issues                    │
│            │ • Hover states missing                     │
│            │ • Color contrast slightly low              │
│            │ • Minor formatting issues                  │
│            │ → FIX IN NEXT SPRINT                       │
├────────────┼────────────────────────────────────────────┤
│ LOW        │ • Enhancement opportunities                │
│            │ • Nice-to-have features                    │
│            │ • Minor polish                             │
│            │ → BACKLOG                                  │
└────────────┴────────────────────────────────────────────┘
```

---

## Success Path

```
┌─────────────────────┐
│  Deployment Ready   │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Run Smoke Test     │
│  (5 min)            │
└─────────────────────┘
         │ PASS
         ▼
┌─────────────────────┐
│  Full Verification  │
│  (Phases 2-7)       │
│  (75 min)           │
└─────────────────────┘
         │ ALL PASS
         ▼
┌─────────────────────┐
│  Document Results   │
│  (15 min)           │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Update GitHub      │
│  Project to "Done"  │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  VERIFICATION       │
│  COMPLETE ✓         │
│                     │
│  Status: PASS       │
│  Issues: 0          │
│  Quality: HIGH      │
└─────────────────────┘
```

---

## Failure Path

```
┌─────────────────────┐
│  Deployment Ready   │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Run Smoke Test     │
│  (5 min)            │
└─────────────────────┘
         │ FAIL
         ▼
┌─────────────────────┐
│  Create CRITICAL    │
│  GitHub Issue       │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Comment on         │
│  Deployment PR      │
│  with Error Details │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  STOP VERIFICATION  │
│  Wait for Fix       │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│  Re-run Smoke Test  │
│  After Fix          │
└─────────────────────┘
```

---

## Quick Reference Commands

```bash
# Navigate
mcp__playwright__browser_navigate --url "URL"

# Snapshot (ALWAYS FIRST!)
mcp__playwright__browser_snapshot

# Check errors
mcp__playwright__browser_console_messages --onlyErrors true

# Screenshot
mcp__playwright__browser_take_screenshot --filename "name.png"

# Interact
mcp__playwright__browser_type --element "desc" --ref "[ref]" --text "..."
mcp__playwright__browser_click --element "desc" --ref "[ref]"

# Resize
mcp__playwright__browser_resize --width 375 --height 667

# Close
mcp__playwright__browser_close
```

---

**For detailed instructions, see:**
- `/workspaces/monorepo/.agent/ui-verification/README.md`
- `/workspaces/monorepo/.agent/ui-verification/quick-reference.md`

---

_Visual guide for CrystalShards UI/UX Verification_
_Created: 2025-10-10_
