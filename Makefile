# PocketLens — common tasks

APP_SCHEME      := PocketLens
APP_PROJECT     := app/PocketLens.xcodeproj
DESTINATION     := platform=macOS
PACKAGES        := Domain Persistence Importing Categorization LLM

.PHONY: help gen build test test-app test-packages clean fmt tools

help:
	@echo "PocketLens — available targets:"
	@echo "  make gen            Regenerate Xcode project from project.yml (requires XcodeGen)"
	@echo "  make build          Build the app"
	@echo "  make test           Run all tests (app + SPM packages)"
	@echo "  make test-app       Run only the app target tests"
	@echo "  make test-packages  Run only SPM package tests"
	@echo "  make clean          Remove build artifacts"
	@echo "  make fmt            Format Swift source (placeholder)"
	@echo "  make tools          Check required tools are installed"

tools:
	@command -v xcodegen >/dev/null 2>&1 || { echo >&2 "xcodegen not found. Run: brew install xcodegen"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo >&2 "xcodebuild not found. Install Xcode."; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo >&2 "swift not found. Install Xcode."; exit 1; }
	@echo "All required tools present."

gen: tools
	cd app && xcodegen generate

build: gen
	xcodebuild -project $(APP_PROJECT) -scheme $(APP_SCHEME) -destination '$(DESTINATION)' build

test: test-packages test-app

test-app: gen
	xcodebuild -project $(APP_PROJECT) -scheme $(APP_SCHEME) -destination '$(DESTINATION)' test

test-packages:
	@for pkg in $(PACKAGES); do \
		echo "→ swift test in packages/$$pkg"; \
		(cd packages/$$pkg && swift test) || exit 1; \
	done

clean:
	rm -rf build DerivedData .build
	@for pkg in $(PACKAGES); do \
		rm -rf packages/$$pkg/.build; \
	done
	rm -rf $(APP_PROJECT)

fmt:
	@echo "fmt: swift-format config pending. No-op for now."
