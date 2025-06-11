![Three bikes, each captioned with version, in order starting from an oldest prototyped from eighteenth century, followed by bicycle from 1870, ending on newest one, used in modern days.](Resources/swift_package_versioning.png)

# Versioning automation for Swift Packages

*(This article assumes you have shell scripts basic knowledge)*

When having several developers working on the same library, no matter if it is in-house or public one, it starts to get very difficult to track all changes and their impact.
Even for one developer, there is a chance of introducing a breaking change marked with a non-major version bump.

The automation of the process may help to prevent potential mistakes, either by fully applying the automated version or as a verification check to the manually proposed one.

## How Swift Package Manager version is represented?

Swift Package Manager (SPM) uses [Semantic Versioning](https://semver.org) (semver). Although Semantic Versioning supports suffixes (like `1.0.1-alpha`), SPM works best with "version core" only (e.g. `1.0.1`). Tagging changes with just a version core allows library consumers to use SPM's `.upToNextMinor(from:)` and `.upToNextMajor(from:)` reliably to specify supported versions.

## How it can be achieved?

The main idea is to compare two public APIs, and based on the difference, propose the next version.

First, setup the script basics:

```bash
#!/usr/bin/env bash

set -Eeuo pipefail

# CONSTANTS

readonly CALL_DIR="$PWD"
readonly SCRIPT_NAME=$(basename -s ".sh" "$0")
readonly TEMP_DIRECTORY=$(cmd echo "$RANDOM")

# FUNCTIONS

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
            echo "${ERROR_MSG_HELP}. Unknown parameter: '${1}'."
            exit 1
        ;;
    esac
done

main
```

The part above allows to use parametrised inputs, like:

```bash
sh propose_next_version.sh \
    --device "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
    --derived-data-path ".build" \
    --scheme "FooBar"
```

Fortunately, Swift has the option to generate the public API file by using followed command:

For packages which uses Apple frameworks, like `UIKIt`:

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

For clean swift packages:

```bash
function build_public_interface() {
    swift build \
        --build-path "$DERIVED_DATA_PATH" \
        -Xswiftc -enable-library-evolution \
        -Xswiftc -emit-module-interface \
        -Xswiftc -no-verify-emitted-module-interface
}
```

Although `$DERIVED_DATA_PATH` is optional, I highly recommend to use it. It prevents data collision issues when script is running by several parallely working jobs on CI runner, beacuse each job has different run directory. We don't want any output visible of that operation, so it is redirected to `/dev/null`.

As we know how to generate the public API file, now it's time to find the change pointing to latest version. To achieve that we go through previous commits from git history, starting search from active branch HEAD, and find the latest version tag. The tag has to be named as plain semver format, e.g. `1.0.1`.

```bash
function get_current_version_tag_name() {
    local current_branch_name
    local last_reference_tag_name

    current_branch_name=$(git rev-parse --abbrev-ref HEAD)
    last_reference_tag_name=$(git tag --merged="$current_branch_name" --list --sort=-version:refname "[0-9]*.[0-9]*.[0-9]*" | head -n 1)
    cat <<< "$last_reference_tag_name"
}
```

Then, check out and copy files from this commit to a separate, temporary folder.

```bash
# Copy change tagged with given version tag to 'tmp/version' directory
git checkout "tags/$version_tag" --force --quiet --recurse-submodules
mkdir -p "$temp_version_directory" && rsync -a --exclude={'.git',"$normalized_temp_dir","$normalized_derived_data_path"} . "$temp_version_directory"

# Checkout back
git checkout - --quiet --recurse-submodules
```

After that, we check out back to the current change and generate two public API files: one from the latest version and one from the introduced change.

```bash
# Get public interface from the previous change
cd "$temp_version_directory"
version_public_interface=$(get_public_interface)
cd "$CALL_DIR"

# Get public interface from the current change
current_public_interface=$(get_public_interface)

# Save public interfaces
mkdir -p "$temp_diff_directory"
version_public_interface_path=$"$temp_diff_directory/version.swiftinterface"
current_public_interface_path=$"$temp_diff_directory/current.swiftinterface"

# Save public API outputs without comments
echo "$version_public_interface" | grep --invert-match '^//' > "$version_public_interface_path"
echo "$current_public_interface" | grep --invert-match '^//' > "$current_public_interface_path"
```

Here the `xcodebuild` command has the additional `OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface"` parameter. By default, the command verifies the generated file. The verification is not needed as we are focusing file generation, not the correctness of generated file for the compiler (example occurance of types named same as package target, known as shadow types). The parameter above disables that file verification.

The last part is to compare two files. We can use `diff` for that.

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

The found semantic version is parsed into three elements (major, minor, patch) using regex matching. Based on the diff analysis:

- If there are breaking changes (lines removed from the API, indicated by `^<` in diff output), increment the major version and reset minor and patch to 0
- If there are only additive changes (new lines added to the API, indicated by `^>` in diff output), increment the minor version and reset patch to 0  
- If there are no API changes, increment only the patch version

Finally, clean up the temporary directory to avoid leaving behind artifacts.

## Examples of usage

The script above can be used to create a tag with every successful merge into the default branch (`main`/`master`).

## Conclusion

With tools builtin either in `swift` or `xcodebuild` with additional scripting, we can automate the next version proposition. It can be used later on for creating a tag, or repository release object.

You may find the complete code for this article in [my  GitHub repository](https://github.com/Filozoff/BlogArticles/tree/master/Article003).

## Further steps

The code discussed in this article is just a brief example, and a few areas could be improved in the future:

- `dependency` versions change scan in `Package.swift` file
- breaking changes detection for macro-generated code for packages with macro targets

For GitHub users, instead of creating your own solution, you may consider a ready action from my repository: [Filozoff/action-swift-propose-next-version](https://github.com/Filozoff/action-swift-propose-next-version). You may check out [the live example of usage in my library](https://github.com/Filozoff/XCTestExtension/blob/master/.github/workflows/ci.yml).
