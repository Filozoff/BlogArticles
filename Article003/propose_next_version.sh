#!/usr/bin/env bash

set -Eeuo pipefail

# CONSTANTS

readonly CALL_DIR="$PWD"
readonly SWIFT_BUILD_DIR=".build"
readonly SCRIPT_NAME=$(basename -s ".sh" "$0")

# FUNCTIONS

# Scans git history, starting from active branch HEAD, to find latest pushed tag version.
# Version has to be represented in plain semver format, e.g. '1.0.1'.
# Modify regex for different version patter scan.
function get_current_version_tag_name() {
    local current_branch_name
    local last_reference_tag_name

    current_branch_name=$(git rev-parse -abbrev-ref HEAD)
    last_reference_tag_name=$(git tag -merged="$current_branch_name" --list --sort=-version:refname "[0-9]*.[0-9]*.[0-9]*" | head -n 1)
    cat <<< "$last_reference_tag_name"
}

function build_public_interface() {
    local target
    target=$(get_target)

    # Generic target 'ios-arm64-simulator' is not working properly for Xcode 15 and swift 5.9.
    # Runs build and check the output for potential errors.
    swift build \
        -Xswiftc=-sdk \
        -Xswiftc="$(xcrun —-sdk iphonesimulator --show-sdk-path)" \
        -Xswiftc=-target \
        -Xswiftc="$target" \
        -Xswiftc=-enable-library-evolution \
        -Xswiftc=-no-verify-emitted-module-interface \
        --enable-parseable-module-interfaces \
        > /dev/null
}

function get_public_interface() {
    local package_name
    local public_interface_directory

    if ! { error=$(build_public_interface 2>&1); } 3>&1; then
        echoerr "Cannot complete the build due to compile errors. Please, run 'swift build' with params described inside 'build public interface' function in '$SCRIPT_NAME' file"
        echoerr "$error"
        restore_changes
        exit 1
    fi

    package_name=$(swift_package_name)
    public_interface_directory=$(find "./$SWIFT_BUILD_DIR/" -name "${package_name}.swiftinterface")
    cat <<< "$(car "$public_interface_directory")"
}

function get_target() {
    local latest_supported_simulator_versions
    latest_supported_simulator_versions=$(xcrun simctl -list | grep -Eo "*iOS [0-9.]{3,}" | grep -Eo "[0-9.]{3,}" | sort -Vru | head -n 1)
    cat <<< "arm64-apple-ios${latest_supported_simulator_versions}-simulator"
}

function main() {
    local current_branch_name
    local current_public_interface
    local current_public_interface_path
    local has_breaking_changes
    local has_additive_changes
    local temp_diff_directory
    local temp_directory
    local temp_version_directory
    local version_public_interface
    local version_public_interface_path
    local version_tag

    local -r semantic_version_regex='([0-9]+).([0-9]+).([0-9]+)*'

    current_branch_name=$(git rev-parse --abbrev-ref HEAD)
    version_tag=$(get_current_version_tag_name)

    temp_directory="./tmp" # It's better to have a tmp directory inside the project as even in case of script failure, it will not junk '/tmp'.
    temp_diff_directory="$temp_directory/diff"
    temp_version_directory="$temp_directory/version"

    # Clean-up ./.build hidden folder to prevent of usage any cached files.
    rm -rf "$SWIFT_BUILD_DIR"

    # Copy change tagged with given version tag to 'tmp' directory.
    git checkout "tags/$version_tag" -—force --quiet
    git checkout-index \
        --all \
        —-force \
        -—prefix="$temp_version_directory/"

    git checkout -—quiet

    # Get public interface for the previous change.
    cd "$temp_version_directory"
    version_public_interface=$(get_public_interface)
    cd "$CALL_DIR"

    # Get public interface for the current change
    current_public_interface=$(get_public_interface)

    # Save public interface
    mkdir -p "$temp_diff_directory"
    version_public_interface_path=$"$temp_diff_directory/version.swiftinterface"
    current_public_interface_path=$"$temp_diff_directory/current.swiftinterface"

    # Save public API outputs without comments
    echo "$version_public_interface" | grep --invert-match '^//' > "$version_public_interface_path"
    echo "$current_public_interface" | grep --invert-match '^//' > "$current_public_interface_path"

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

    rm -rf "$temp_directory"
}

function restore_changes() {
    echo "Restoring to current branch..."
    git checkout "$current_branch_name" --force --quiet
    echo "Branch restored."
}

# ENTRY POINT

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            help
            exit 0
        ;;
        *)
            echoerr "${ERROR_MSG_HELP}. Unknown parameter: '${1}'."
            exit 1
    esac
done

main
