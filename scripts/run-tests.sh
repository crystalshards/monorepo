#!/bin/bash
set -e

echo "🧪 Running CrystalShards Platform Tests"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in CI
if [ "$CI" = "true" ]; then
    print_status "Running in CI environment"
    # Use environment variables for database connections
    DATABASE_URL_PREFIX=${DATABASE_URL_PREFIX:-"postgresql://postgres:postgres@localhost:5432"}
    REDIS_URL=${REDIS_URL:-"redis://localhost:6379"}
else
    print_status "Running in local environment"
    # Use local defaults
    DATABASE_URL_PREFIX="postgresql://postgres:password@localhost:5432"
    REDIS_URL="redis://localhost:6379"
fi

# Test configuration
export DATABASE_URL_REGISTRY="${DATABASE_URL_PREFIX}/crystalshards_test"
export DATABASE_URL_DOCS="${DATABASE_URL_PREFIX}/crystaldocs_test"
export DATABASE_URL_GIGS="${DATABASE_URL_PREFIX}/crystalgigs_test"

# Test Stripe keys
export STRIPE_SECRET_KEY="sk_test_dummy"
export STRIPE_PUBLISHABLE_KEY="pk_test_dummy"

# Check dependencies
print_status "Checking dependencies..."

if ! command -v crystal &> /dev/null; then
    print_error "Crystal compiler not found. Please install Crystal."
    exit 1
fi

if ! command -v shards &> /dev/null; then
    print_error "Shards package manager not found."
    exit 1
fi

print_success "Dependencies OK"

# Install Crystal dependencies
print_status "Installing Crystal dependencies..."

cd "$(dirname "$0")/.."

for app in shards-registry shards-docs gigs worker; do
    if [ -d "apps/$app" ]; then
        print_status "Installing dependencies for $app..."
        cd "apps/$app"
        shards install --production
        cd ../..
    fi
done

if [ -d "libraries/models" ]; then
    print_status "Installing dependencies for shared models..."
    cd "libraries/models"
    shards install --production
    cd ../..
fi

print_success "Crystal dependencies installed"

# Run Crystal specs
print_status "Running Crystal unit and integration tests..."

test_results=()

for app in shards-registry shards-docs gigs worker; do
    if [ -d "apps/$app/spec" ]; then
        print_status "Running tests for $app..."
        cd "apps/$app"
        
        # Set app-specific environment variables
        case $app in
            "shards-registry")
                export DATABASE_URL="$DATABASE_URL_REGISTRY"
                export REDIS_URL="$REDIS_URL/0"
                ;;
            "shards-docs")
                export DATABASE_URL="$DATABASE_URL_DOCS"
                export REDIS_URL="$REDIS_URL/1"
                ;;
            "gigs")
                export DATABASE_URL="$DATABASE_URL_GIGS"
                export REDIS_URL="$REDIS_URL/2"
                ;;
            "worker")
                export DATABASE_URL="$DATABASE_URL_REGISTRY"
                export REDIS_URL="$REDIS_URL/3"
                ;;
        esac
        
        if crystal spec --error-trace; then
            print_success "Tests passed for $app"
            test_results+=("$app:PASS")
        else
            print_error "Tests failed for $app"
            test_results+=("$app:FAIL")
        fi
        cd ../..
    else
        print_warning "No tests found for $app"
        test_results+=("$app:SKIP")
    fi
done

# Check Crystal formatting
print_status "Checking Crystal code formatting..."
if crystal tool format --check apps/ libraries/; then
    print_success "Crystal code formatting is correct"
else
    print_error "Crystal code formatting issues found"
    print_status "Run 'crystal tool format apps/ libraries/' to fix"
fi

# Run E2E tests if available
if [ -d "tests/e2e" ]; then
    print_status "Running End-to-End tests..."
    cd "tests/e2e"
    
    if [ -f "package.json" ]; then
        if command -v npm &> /dev/null; then
            if [ ! -d "node_modules" ]; then
                print_status "Installing E2E test dependencies..."
                npm ci
            fi
            
            # Install Playwright browsers if not in CI
            if [ "$CI" != "true" ]; then
                npx playwright install
            fi
            
            print_status "Running Playwright tests..."
            if npx playwright test; then
                print_success "E2E tests passed"
                test_results+=("e2e:PASS")
            else
                print_error "E2E tests failed"
                test_results+=("e2e:FAIL")
            fi
        else
            print_warning "npm not found, skipping E2E tests"
            test_results+=("e2e:SKIP")
        fi
    fi
    cd ../..
else
    print_warning "No E2E tests found"
fi

# Print summary
echo ""
print_status "Test Results Summary:"
echo "═════════════════════"

failed_tests=0
total_tests=0

for result in "${test_results[@]}"; do
    app=$(echo "$result" | cut -d':' -f1)
    status=$(echo "$result" | cut -d':' -f2)
    total_tests=$((total_tests + 1))
    
    case $status in
        "PASS")
            print_success "$app: PASSED"
            ;;
        "FAIL")
            print_error "$app: FAILED"
            failed_tests=$((failed_tests + 1))
            ;;
        "SKIP")
            print_warning "$app: SKIPPED"
            ;;
    esac
done

echo ""
if [ $failed_tests -eq 0 ]; then
    print_success "All tests completed successfully! 🎉"
    exit 0
else
    print_error "$failed_tests out of $total_tests test suites failed"
    exit 1
fi