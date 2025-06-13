![Three bikes, each captioned with version, in order starting from an oldest prototyped from eighteenth century, followed by bicycle from 1870, ending on newest one, used in modern days.](Resources/swift_package_versioning.png)

# Versioning automation for Swift Packages

*(This article assumes you have basic knowledge of shell scripts)*

When multiple developers work on the same library, whether it's an in-house or public project, tracking changes and their impact becomes increasingly challenging. Even for a single developer, there's a risk of introducing breaking changes without properly marking them with a major version bump.

Automating this process can help prevent potential mistakes, either by fully implementing automated versioning or by verifying manually proposed versions.

## How is Swift Package Manager version represented?

Swift Package Manager (SPM) uses [Semantic Versioning](https://semver.org) (semver). While Semantic Versioning supports suffixes (like `1.0.1-alpha`), SPM works best with the "version core" only (e.g., `1.0.1`). Tagging changes with just the version core enables library consumers to reliably use SPM's `.upToNextMinor(from:)` and `.upToNextMajor(from:)` to specify supported versions.

## How it can be achieved?

Let's break it down into steps:
- **Compare two API states**: Extract the public interface from both the latest tagged version and the current codebase
- **Analyze the differences**: Identify what has been added, modified, or removed in the public API
- **Apply semantic versioning rules**: Based on the type of changes detected, determine whether the next version should be:
  - **Patch** (x.x.Z) - for bug fixes and internal changes that don't affect the public API
  - **Minor** (x.Y.x) - for new features that are backward compatible
  - **Major** (X.x.x) - for breaking changes that require consumer code updates
- **Propose the version**: Generate the next appropriate version number following semantic versioning principles

### Script foundation and argument parsing

First, setup the script basics:

```bash
#!/usr/bin/env bash

set -Eeuo pipefail
trap 'error_handler ${FUNCNAME-main context} ${LINENO} $?' ERR

# CONSTANTS

readonly CALL_DIR="$PWD"
readonly SCRIPT_NAME=$(basename -s ".sh" "$0")
readonly TEMP_DIRECTORY="tmp$RANDOM"

# FUNCTIONS

function error_handler() {
    echo "$SCRIPT_NAME.sh: in '$1()', line $2: error: $3"
    reset
    exit 1
}

function main() {
}

# ENTRY POINT

while [[ $# -gt 0 ]]; do
    case $1 in
        # Device for which public interface is created. Use value supported by `-destination` argument from `xcodebuild archive`,
        # e.g. `platform=iOS Simulator,name=iPhone 14,OS=17.0`.
        -d|--device)
            DESTINATION=${2}
            shift 2
        ;;
        # Derived data path (optional).
        -r|--derived-data-path)
            DERIVED_DATA_PATH=${2}
            ARCHIVE_PATH="$DERIVED_DATA_PATH/archive"
            shift 2
        ;;
        # Package scheme name. For packages with multiple targets, it may be required to add `-Package` suffix.
        # Example: your package is named `ClientService` and has two targets inside: `ClientServiceDTOs` and `ClientServiceAPI`.
        # Then, your target would be `ClientService-Package`.
        -s|--scheme)
            SCHEME=${2}
            shift 2
        ;;
        *)
            echo "Unknown parameter: '${1}'."
            exit 1
        ;;
    esac
done

main
```

The argument parsing allows parametrized inputs, like:

```bash
sh propose_next_version.sh \
    --device "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
    --derived-data-path ".build" \
    --scheme "FooBar"
```

Although `$DERIVED_DATA_PATH` is optional, I highly recommend using it. Due to different directory (I suggest local, e.g. `./.build`) it prevents data collision issues when the script runs in parallel CI jobs on one runner.

Next, add some helpers which will be used later on:

```bash
function reset() {
    cd "$CALL_DIR"
    rm -rf "$TEMP_DIRECTORY" > /dev/null
}

# Extract package name from Package.swift
function swift_package_name() {
    swift package describe --type json | jq -r .name
}
```

These helper functions serve two purposes: `reset()` cleans up temporary files and returns to the original directory, while `swift_package_name()` extracts the package name from `Package.swift` using Swift's built-in package description and jq for JSON parsing.
Make sure you have [`jq`](https://github.com/jqlang/jq) installed.

### Finding the current version tag

We need to identify the latest version to compare against. The script scans git history starting from the active branch HEAD to find the latest version tag:

```bash
function get_current_version_tag_name() {
    local current_branch_name
    local last_reference_tag_name

    current_branch_name=$(git rev-parse --abbrev-ref HEAD)
    last_reference_tag_name=$(git tag --merged="$current_branch_name" --list --sort=-version:refname "[0-9]*.[0-9]*.[0-9]*" | head -n 1)
    cat <<< "$last_reference_tag_name"
}
```

This function:
1. Gets the current branch name. Usually it is default branch (`main`/`master`)
2. Lists all tags merged into the current branch that match semver pattern
3. Sorts them by version in reverse order (`-version:refname`), from latest to oldest
4. Takes the first (latest) one

### Generating public API interfaces

Swift provides built-in capabilities to generate public API files. We could have two different approaches depending on the package type:

For packages using Apple frameworks (like `UIKit`):

```bash
function build_public_interface() {
    xcodebuild \
        -archivePath "$ARCHIVE_PATH" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -destination "$DESTINATION" \
        -scheme "$SCHEME" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface" \
        archive | xcbeautify
}
```
Be aware that the above solution works only on macOS.

For clean Swift packages (universal):

```bash
function build_public_interface() {
    swift build \
        --build-path "$DERIVED_DATA_PATH" \
        -Xswiftc -enable-library-evolution \
        -Xswiftc -emit-module-interface \
        -Xswiftc -no-verify-emitted-module-interface | xcbeautify
}
```

By default, after generating public interface, compiler verifies it. The `-no-verify-emitted-module-interface"` parameter disables that verification. 
In our case we only need generated file and additional correctness of it is not needed.
`xcbeautify` is not a mandatory here, but it is nice to have. It prints nicely the building output which we may use in case of encountered build error.

### Extracting the public interface

After building the package, we need to extract its public interface for comparison. The function below automates this process:

```bash
function get_public_interface() {
    local package_name
    local public_interface_directory

    if ! { error=$(build_public_interface 2>&1); }; then
        echo "$error"
        echo "Cannot complete the build due to the compile error. Check logs above."
        exit 1
    fi

    package_name=$(swift_package_name)
    public_interface_directory=$(find "./$DERIVED_DATA_PATH/" -name "${package_name}.swiftinterface")
    cat <<<"$(cat "$public_interface_directory")"
}
```

This function:
- Builds the package and captures any compilation errors, exiting early if the build fails.
- Determines the package name and locates the generated `.swiftinterface` file.
- Outputs the contents of the public interface, which will be used for API comparison.

### Creating temporary workspaces and comparing versions

Let's build now the `main` function. First, define local variabales, get branch name and latest version tag. Setup reporary directories and cleanup derived-data folder to avoid any possible data issues:

```bash
local current_branch_name
local current_public_interface
local current_public_interface_path
local has_breaking_changes
local has_additive_changes
local normalized_derived_data_path
local normalized_temp_dir
local temp_diff_directory
local temp_version_directory
local version_public_interface
local version_public_interface_path
local version_tag

local -r semantic_version_regex='([0-9]+).([0-9]+).([0-9]+)'

current_branch_name=$(git rev-parse --abbrev-ref HEAD)
version_tag=$(get_current_version_tag_name)

normalized_temp_dir=$(echo "$TEMP_DIRECTORY" | sed 's/^\.\///')
normalized_derived_data_path=$(echo "$DERIVED_DATA_PATH" | sed 's/^\.\///')

temp_diff_directory="$TEMP_DIRECTORY/diff"
temp_version_directory="$TEMP_DIRECTORY/version"

# Clean up derived data directory to prevent usage of any cached files
rm -rf "$DERIVED_DATA_PATH"
```

Next, create temporary copies of both the tagged version and current changes. They are going to be used for diffing later:

```bash
# Copy change tagged with given version tag to temporary directory
git clone "$CALL_DIR" --branch "$version_tag" --single-branch "$temp_version_directory" --quiet --recurse-submodules -c advice.detachedHead=false

# Get public interface from the previous version
cd "$temp_version_directory"
version_public_interface=$(get_public_interface)

# Go back to the project root.
cd "$CALL_DIR"

# Get public interface from the current changes
current_public_interface=$(get_public_interface)

# Save public interfaces for comparison
mkdir -p "$temp_diff_directory"
version_public_interface_path="$temp_diff_directory/version.swiftinterface"
current_public_interface_path="$temp_diff_directory/current.swiftinterface"

# Save public API outputs without comments (comments can change without affecting API)
echo "$version_public_interface" | grep --invert-match '^//' > "$version_public_interface_path"
echo "$current_public_interface" | grep --invert-match '^//' > "$current_public_interface_path"
```

### Analyzing differences and proposing versions

The final step compares the two interface files using `diff`:

```bash
# Make public interfaces diffs
has_breaking_changes=$(diff "$version_public_interface_path" "$current_public_interface_path" | grep -c -i "^<" || true)
has_additive_changes=$(diff "$version_public_interface_path" "$current_public_interface_path" | grep -c -i "^>" || true)

# Create version based on diff output
if [[ ! $version_tag =~ $semantic_version_regex ]]; then
    cat <<< "$version_tag"
else
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"

    if [[ $has_breaking_changes -gt 0 ]]; then
        major=$((major+1))
        minor=0
        patch=0
    elif [[ $has_additive_changes -gt 0 ]]; then
        minor=$((minor+1))
        patch=0
    else
        patch=$((patch+1))
    fi

    cat <<< "${major}.${minor}.${patch}"
fi
```

The semantic version is parsed using regex. Based on the diff analysis:
- **Breaking changes** (lines removed from the API, indicated by `^<` in diff output): increment major version, reset minor and patch to 0
- **Additive changes** (new lines added to the API, indicated by `^>` in diff output): increment minor version, reset patch to 0  
- **No API changes**: increment only the patch version

### Cleanup

Finally, clean up the temporary directory to avoid leaving behind artifacts:

```bash
reset
```

## Examples of usage

The script above can be used to create a tag with every successful merge into the default branch (`main`/`master`). Here's a complete usage example:

```bash
# Basic usage
./propose_next_version.sh \
    --device "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
    --derived-data-path ".build" \
    --scheme "MyPackage"

# In CI/CD pipeline
NEXT_VERSION=$(./propose_next_version.sh --device "platform=iOS Simulator,name=iPhone 16,OS=18.0" --derived-data-path ".build" --scheme "MyPackage")
git tag "$NEXT_VERSION"
git push origin "$NEXT_VERSION"
```

## Conclusion

By combining tools built into either `swift` or `xcodebuild` with shell scripting, we can automate next version proposals. This approach can be used for creating tags or repository release objects with confidence that semantic versioning rules are properly followed.

The automated approach reduces human error in version management and ensures consistent versioning practices across development teams.

You may find the complete code for this article in [my GitHub repository](https://github.com/Filozoff/BlogArticles/tree/master/Article003).

## Further steps

The code discussed in this article provides a foundation that can be improved in several areas:
- **Dependency analysis**: Scan `Package.swift` for dependency version changes that might affect compatibility
- **Macro support**: Enhanced breaking change detection for packages with macro targets, as macro-generated code might not be captured in standard interface files
- **Custom API analysis**: More sophisticated parsing for complex API changes that might not be obvious from simple diff analysis

For GitHub users, instead of implementing this from scratch, consider using a ready-made action from my repository: [Filozoff/action-swift-propose-next-version](https://github.com/Filozoff/action-swift-propose-next-version). You can see [a live example of its usage](https://github.com/Filozoff/XCTestExtension/blob/master/.github/workflows/ci.yml) in my library.
