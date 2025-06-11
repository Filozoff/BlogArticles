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

function reset() {
    cd "$CALL_DIR"
    rm -rf "$TEMP_DIRECTORY" > /dev/null
}

# Extract package name from Package.swift
function swift_package_name() {
    swift package describe --type json | jq -r .name
}

# Scans git history, starting from active branch HEAD, to find latest pushed tag version.
# Version has to be represented in plain semver format, e.g. '1.0.1'.
# Modify regex for different version pattern scan.
function get_current_version_tag_name() {
    local current_branch_name
    local last_reference_tag_name

    current_branch_name=$(git rev-parse --abbrev-ref HEAD)
    last_reference_tag_name=$(git tag --merged="$current_branch_name" --list --sort=-version:refname "[0-9]*.[0-9]*.[0-9]*" | head -n 1)
    cat <<< "$last_reference_tag_name"
}

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

function main() {
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

    # Copy change tagged with given version tag to 'tmp/version' directory
    git clone "$CALL_DIR" --branch "$version_tag" --single-branch "$temp_version_directory" --quiet --recurse-submodules -c advice.detachedHead=false

    # Get public interface from the previous change
    cd "$temp_version_directory"
    version_public_interface=$(get_public_interface)

    # Go back to the project root.
    # Get public interface from the current change
    cd "$CALL_DIR"
    current_public_interface=$(get_public_interface)

    # Save public interfaces
    mkdir -p "$temp_diff_directory"
    version_public_interface_path="$temp_diff_directory/version.swiftinterface"
    current_public_interface_path="$temp_diff_directory/current.swiftinterface"

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

    # Cleanup
    reset
}

# ENTRY POINT

while [[ $# -gt 0 ]]; do
    case $1 in
        # Device for which public interface is created. Use value supported by `-destination` argument in `xcodebuild archive`.
        # E.g. `platform=iOS Simulator,name=iPhone 14,OS=17.0`.
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
