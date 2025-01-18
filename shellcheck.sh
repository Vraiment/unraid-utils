#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Propagate exit code on a pipeline
set -x # Print commands and their arguments as they are executed.

function main() {
    ensure-shellcheck
    validate-files
}

function ensure-shellcheck() {
    if ! command -v shellcheck; then
        >&2 echo shellcheck not found
        exit 1
    fi
}

function validate-files() {
    local files

    files=(
        shellcheck.sh
        bin/backup.sh
    )
    readonly files

    shellcheck "${files[@]}"
}

main "$@"
