#!/bin/bash
# CrystalShards UI/UX Verification Execution Script
# Run this script once deployment completes
# Reference: /workspaces/monorepo/.agent/ui-verification/crystalshards-playwright-verification-plan.md

set -e

BASE_URL="https://crystalshards.org"
RESULTS_DIR="/workspaces/monorepo/.agent/ui-verification/results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=========================================="
echo "CrystalShards UI/UX Verification"
echo "=========================================="
echo "Target: $BASE_URL"
echo "Timestamp: $TIMESTAMP"
echo "Results: $RESULTS_DIR"
echo "=========================================="
echo ""

# Create results directory
mkdir -p "$RESULTS_DIR"

# Check deployment status
echo "Step 0: Verifying deployment status..."
if curl -I "$BASE_URL" 2>/dev/null | grep -q "200 OK"; then
  echo "✓ Deployment is live"
else
  echo "✗ Deployment not accessible"
  echo "Please verify deployment status before running this script."
  exit 1
fi

echo ""
echo "=========================================="
echo "SMOKE TEST - Quick Sanity Check"
echo "=========================================="
echo ""

# Function to run Playwright commands
# Note: This is a template - actual execution requires MCP tool calls

run_smoke_test() {
  echo "Testing Homepage..."
  # mcp__playwright__browser_navigate --url "$BASE_URL"
  # mcp__playwright__browser_snapshot
  # mcp__playwright__browser_console_messages --onlyErrors true
  echo "  → Navigate to $BASE_URL"
  echo "  → Capture snapshot"
  echo "  → Check console errors"

  echo ""
  echo "Testing Browse Page..."
  # mcp__playwright__browser_navigate --url "$BASE_URL/shards"
  # mcp__playwright__browser_snapshot
  # mcp__playwright__browser_console_messages --onlyErrors true
  echo "  → Navigate to $BASE_URL/shards"
  echo "  → Capture snapshot"
  echo "  → Check console errors"

  echo ""
  echo "Testing Package Detail Page..."
  # Note: Replace 'lucky' with actual shard name from database
  # mcp__playwright__browser_navigate --url "$BASE_URL/shards/lucky"
  # mcp__playwright__browser_snapshot
  # mcp__playwright__browser_console_messages --onlyErrors true
  echo "  → Navigate to $BASE_URL/shards/[SHARD_NAME]"
  echo "  → Capture snapshot"
  echo "  → Check console errors"

  echo ""
  echo "✓ Smoke test complete"
}

run_homepage_verification() {
  echo ""
  echo "=========================================="
  echo "HOMEPAGE - Full Verification"
  echo "=========================================="
  echo ""

  echo "1. Navigate to homepage"
  echo "   mcp__playwright__browser_navigate --url \"$BASE_URL\""

  echo "2. Capture accessibility snapshot"
  echo "   mcp__playwright__browser_snapshot"

  echo "3. Check console errors"
  echo "   mcp__playwright__browser_console_messages --onlyErrors true"

  echo "4. Screenshot (desktop 1920×1080)"
  echo "   mcp__playwright__browser_take_screenshot \\"
  echo "     --filename \"crystalshards-homepage-desktop-$TIMESTAMP.png\""

  echo "5. Test search functionality"
  echo "   - Get search input ref from snapshot"
  echo "   - Type search query"
  echo "   - Submit form"
  echo "   - Verify redirect to /shards?query=..."

  echo "6. Test 'View All Shards' link"
  echo "   - Get link ref from snapshot"
  echo "   - Click link"
  echo "   - Verify navigation to /shards"

  echo "7. Test mobile viewport (375×667)"
  echo "   mcp__playwright__browser_resize --width 375 --height 667"
  echo "   mcp__playwright__browser_snapshot"
  echo "   mcp__playwright__browser_take_screenshot \\"
  echo "     --filename \"crystalshards-homepage-mobile-$TIMESTAMP.png\""

  echo "8. Test tablet viewport (768×1024)"
  echo "   mcp__playwright__browser_resize --width 768 --height 1024"
  echo "   mcp__playwright__browser_snapshot"

  echo "9. Reset to desktop viewport"
  echo "   mcp__playwright__browser_resize --width 1920 --height 1080"

  echo "10. Check network requests"
  echo "    mcp__playwright__browser_network_requests"

  echo ""
  echo "✓ Homepage verification complete"
}

run_browse_verification() {
  echo ""
  echo "=========================================="
  echo "BROWSE/SEARCH - Full Verification"
  echo "=========================================="
  echo ""

  echo "1. Navigate to browse page"
  echo "   mcp__playwright__browser_navigate --url \"$BASE_URL/shards\""

  echo "2. Capture snapshot"
  echo "   mcp__playwright__browser_snapshot"

  echo "3. Screenshot"
  echo "   mcp__playwright__browser_take_screenshot \\"
  echo "     --filename \"crystalshards-browse-desktop-$TIMESTAMP.png\""

  echo "4. Test search"
  echo "   - Type in search input"
  echo "   - Submit"
  echo "   - Verify results"

  echo "5. Test sorting"
  echo "   - Select 'Most Popular'"
  echo "   - Apply"
  echo "   - Verify URL params"

  echo "6. Test license filter"
  echo "   - Select 'MIT'"
  echo "   - Apply"

  echo "7. Test min stars filter"
  echo "   - Select '50+'"
  echo "   - Apply"

  echo "8. Test has docs checkbox"
  echo "   - Check checkbox"
  echo "   - Apply"

  echo "9. Test Clear Filters"
  echo "   - Click Clear Filters"
  echo "   - Verify reset"

  echo "10. Test pagination (if exists)"
  echo "    - Click Next"
  echo "    - Verify page 2"
  echo "    - Click Previous"

  echo "11. Test empty state"
  echo "    mcp__playwright__browser_navigate \\"
  echo "      --url \"$BASE_URL/shards?query=nonexistentshardxyz123\""
  echo "    mcp__playwright__browser_snapshot"

  echo "12. Test responsive design"
  echo "    - Mobile (375×667)"
  echo "    - Tablet (768×1024)"

  echo ""
  echo "✓ Browse/Search verification complete"
}

run_detail_verification() {
  echo ""
  echo "=========================================="
  echo "PACKAGE DETAIL - Full Verification"
  echo "=========================================="
  echo ""

  echo "Note: Replace 'lucky' with actual shard name from database"
  echo ""

  echo "1. Navigate to package detail"
  echo "   mcp__playwright__browser_navigate \\"
  echo "     --url \"$BASE_URL/shards/lucky\""

  echo "2. Capture snapshot"
  echo "   mcp__playwright__browser_snapshot"

  echo "3. Screenshot"
  echo "   mcp__playwright__browser_take_screenshot \\"
  echo "     --filename \"crystalshards-detail-desktop-$TIMESTAMP.png\""

  echo "4. Verify header section"
  echo "   - Shard title (h1)"
  echo "   - Version badge"
  echo "   - Description"
  echo "   - Stats (stars, downloads, license)"

  echo "5. Verify installation section"
  echo "   - Code blocks visible"
  echo "   - shard.yml snippet correct"
  echo "   - shards install command present"

  echo "6. Verify README section"
  echo "   - Content displays"
  echo "   - Links work"

  echo "7. Verify dependencies section (if any)"
  echo "   - Runtime dependencies listed"
  echo "   - Dev dependencies listed"
  echo "   - Dependency links work"

  echo "8. Verify sidebar links"
  echo "   - Repository link (external)"
  echo "   - Homepage link (external)"
  echo "   - Documentation link (external)"
  echo "   - All have target='_blank'"

  echo "9. Verify versions section"
  echo "   - Version list displays"
  echo "   - Dates formatted"
  echo "   - Yanked versions styled differently"

  echo "10. Verify metadata section"
  echo "    - Created date"
  echo "    - Updated date"
  echo "    - Crystal version"

  echo "11. Test external links"
  echo "    - Verify target='_blank' attribute"
  echo "    mcp__playwright__browser_evaluate \\"
  echo "      --function \"() => {"
  echo "        const links = document.querySelectorAll('a[href^=\\\"http\\\"]');"
  echo "        return Array.from(links).every(link => link.target === '_blank');"
  echo "      }\""

  echo "12. Test responsive design"
  echo "    - Mobile (375×667)"
  echo "    - Tablet (768×1024)"
  echo "    - Verify sidebar moves below main on mobile"

  echo ""
  echo "✓ Package Detail verification complete"
}

run_accessibility_verification() {
  echo ""
  echo "=========================================="
  echo "ACCESSIBILITY - Full Verification"
  echo "=========================================="
  echo ""

  echo "1. Test keyboard navigation"
  echo "   - Tab through all interactive elements"
  echo "   - Verify focus indicators visible"
  echo "   - Test Enter/Space activation"

  echo "2. Check heading hierarchy"
  echo "   mcp__playwright__browser_evaluate \\"
  echo "     --function \"() => {"
  echo "       const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');"
  echo "       return Array.from(headings).map(h => ({"
  echo "         tag: h.tagName,"
  echo "         text: h.textContent.trim()"
  echo "       }));"
  echo "     }\""

  echo "3. Check ARIA labels"
  echo "   - Verify interactive elements have labels"
  echo "   - Check form labels"

  echo "4. Check alt text on images"
  echo "   mcp__playwright__browser_evaluate \\"
  echo "     --function \"() => {"
  echo "       const images = document.querySelectorAll('img');"
  echo "       return Array.from(images).map(img => ({"
  echo "         src: img.src,"
  echo "         alt: img.alt,"
  echo "         hasAlt: img.hasAttribute('alt')"
  echo "       }));"
  echo "     }\""

  echo "5. Test form accessibility"
  echo "   - Labels associated with inputs"
  echo "   - Error messages announced"

  echo ""
  echo "✓ Accessibility verification complete"
}

run_performance_verification() {
  echo ""
  echo "=========================================="
  echo "PERFORMANCE - Full Verification"
  echo "=========================================="
  echo ""

  echo "1. Measure homepage load time"
  echo "   mcp__playwright__browser_navigate --url \"$BASE_URL\""
  echo "   mcp__playwright__browser_evaluate \\"
  echo "     --function \"() => {"
  echo "       const perfData = window.performance.timing;"
  echo "       const pageLoadTime = perfData.loadEventEnd - perfData.navigationStart;"
  echo "       return {"
  echo "         pageLoadTime: pageLoadTime,"
  echo "         domContentLoaded: perfData.domContentLoadedEventEnd - perfData.navigationStart,"
  echo "         ttfb: perfData.responseStart - perfData.navigationStart"
  echo "       };"
  echo "     }\""

  echo "2. Measure browse page load time"
  echo "   (Repeat for /shards)"

  echo "3. Measure package detail load time"
  echo "   (Repeat for /shards/[name])"

  echo "4. Check network requests"
  echo "   mcp__playwright__browser_network_requests"
  echo "   - Identify slow requests"
  echo "   - Check for blocking resources"

  echo "5. Verify load times < 2 seconds"
  echo "   - Homepage: [RESULT]"
  echo "   - Browse: [RESULT]"
  echo "   - Detail: [RESULT]"

  echo ""
  echo "✓ Performance verification complete"
}

# Main execution flow
main() {
  echo "This script provides a guide for manual Playwright verification."
  echo "Each section shows the MCP commands to run."
  echo ""
  echo "To execute, copy and paste commands into Claude, or"
  echo "convert this to actual MCP tool calls."
  echo ""

  read -p "Run smoke test guide? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    run_smoke_test
  fi

  read -p "Run homepage verification guide? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    run_homepage_verification
  fi

  read -p "Run browse/search verification guide? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    run_browse_verification
  fi

  read -p "Run package detail verification guide? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    run_detail_verification
  fi

  read -p "Run accessibility verification guide? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    run_accessibility_verification
  fi

  read -p "Run performance verification guide? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    run_performance_verification
  fi

  echo ""
  echo "=========================================="
  echo "Verification Guide Complete"
  echo "=========================================="
  echo ""
  echo "Next Steps:"
  echo "1. Review results and create GitHub issues for any problems"
  echo "2. Use issue templates in verification plan document"
  echo "3. Create summary document with verification results"
  echo "4. Comment on GitHub issues with verification status"
  echo "5. Update GitHub Project status to 'Done' if passed"
  echo ""
  echo "Results directory: $RESULTS_DIR"
  echo "Verification plan: /workspaces/monorepo/.agent/ui-verification/crystalshards-playwright-verification-plan.md"
  echo ""
}

# Run main function
main
