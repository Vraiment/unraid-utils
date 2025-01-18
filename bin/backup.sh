#!/bin/bash

# Fail when commands exit unsuccessfully.
set -o errexit

# Fail when using an undefined variable.
set -o nounset

# Fail if commands fail as part of a pipeline.
set -o pipefail

# Print every statement to stderr
set -x

function logInfo() {
    echo "$@"
}

function logError() {
    >&2 echo "$@"
}

function getVmStatus() {
    virsh list --all | grep "$1" | tr -s ' ' | cut -d ' ' -f 4-
}

function shutdownVm() {
    local -r vmName="$1"

    if [ "$(getVmStatus "$vmName")" == 'shut off' ]; then
        logInfo "VM $vmName is already shutdown..."
        return 0
    fi

    virsh shutdown "$vmName"

    local i
    local waitSeconds=10
    for ((i=0; i<="$waitSeconds"; ++i)); do
        if [ "$(getVmStatus "$vmName")" == 'shut off' ]; then
            logInfo "VM $vmName has shutdown!"
            return 0
        fi

        logInfo "Waiting for VM $vmName to shutdown..."
        sleep 1
    done

    logError "VM $vmName did not shutdown!"
    return 1
}

function getBackupDevice() {
    blkid --output device --match-token UUID="$1"
}

function mountBackup() {
    local -r backupDeviceUuid="$1"
    local -r backupMountDir="$2"
    local backupDevice

    local i
    local backupDeviceFound='false'
    local waitSeconds=10
    for ((i=0; i<="$waitSeconds"; ++i)); do
        logError "Waiting for device with UUID $backupDeviceUuid to show up..."

        if backupDevice="$(getBackupDevice "$backupDeviceUuid")"; then
            backupDeviceFound='true'
            break
        fi

        sleep 1
    done

    if [ "$backupDeviceFound" != 'true' ]; then
        logError "Device with UUID $backupDeviceUuid didn't show up!"
        return 1
    fi

    mkdir --parents "$backupMountDir"

    if mount --types ntfs-3g "$backupDevice" "$backupMountDir"; then
        logInfo "Successfully mounted $backupDevice on $backupMountDir"
    else
        logError "Failed to mount $backupDevice on $backupMountDir"
        return 1
    fi
}

function performBackup() {
    local -r sharesLocation=/mnt/user
    local -r backupMountDir="$1"
    local -a sharesToBackup
    IFS=',' read -r -a sharesToBackup <<< "$2"
    readonly sharesToBackup

    logInfo "Backup shares from $sharesLocation to $backupMountDir"

    local shareToBackup
    for shareToBackup in "${sharesToBackup[@]}"; do
        logInfo "Backing up share $shareToBackup..."
        # -a = recursive (recurse into directories), links (copy symlinks as symlinks), perms (preserve permissions),
        #      times (preserve modification times), group (preserve group), owner (preserve owner),
        #      preserve device files, and preserve special files.
        # -v = verbose. The reason I think verbose is important is so you can see exactly what rsync is backing up.
        #      Think about this: What if your hard drive is going bad, and starts deleting files without your knowledge,
        #      then you run your rsync script and it pushes those changes to your backups, thereby deleting all
        #      instances of a file that you did not want to get rid of?
        # -delete = This tells rsync to delete any files that are in Directory2 that aren’t in Directory1. If you choose
        #           to use this option, I recommend also using the verbose options, for reasons mentioned above.
        rsync -av --delete-after "$sharesLocation/$shareToBackup" "$backupMountDir"
    done
}

function umountBackup() {
    local -r backupMountDir="$1"

    if ! umount "$backupMountDir"; then
        logError "Failed to umount $backupMountDir!"
        return 1
    fi
}

function startVm() {
    local -r vmName="$1"

    if ! virsh start "$vmName"; then
        logError "Failed to start $vmName!"
        return 1
    fi
}

function parseVmName() {
    local found, value
    found=false

    while [ "$#" -gt 0 ]; do
        value="$1"
        shift

        case "$value" in
            --vm-name|-vm)
                found=true
                break
                ;;
        esac
    done

    if [ $found = false ] || [ $# -eq 0 ]; then
        logError "No VM name argument found"
        return 1
    fi

    echo "$1"
}

function parseBackupDeviceUuid() {
    local found, value
    found=false

    while [ "$#" -gt 0 ]; do
        value="$1"
        shift

        case "$value" in
            --backup-device-uuid|-bdu)
                found=true
                break
                ;;
        esac
    done

    if [ $found = false ] || [ $# -eq 0 ]; then
        logError "No backup device UUID argument found"
        return 1
    fi

    echo "$1"
}

function parseSharesToBackup() {
    local found, value
    found=false

    while [ "$#" -gt 0 ]; do
        value="$1"
        shift

        case "$value" in
            --shares-to-backup|-s2b)
                found=true
                break
                ;;
        esac
    done

    if [ $found = false ] || [ $# -eq 0 ]; then
        logError "No shares to backup argument found"
        return 1
    fi

    echo "$1"

}

function printHelp() {
    cat<<EOH
Usage: $0 [OPTIONS]

Backups Unraid shares into a disk used by a VM.

This scripts makes the assumption it's running as root on an Unraid. It will stop
the VM with the given name and perform an rsync of the shares into the device with
the given UUID. Then it will restart the VM. This is because there's an assumption
of the device being mounted into the VM.

Options:
  --vm-name, -vm             The VM that will be temporarily stopped for the backup
  --backup-device-uuid, -bdu The UUID of the device to mount
  --shares-to-backup, -s2b   Comma separated list of the Unraid shares to backup

Examples:
  # $0 -vm Backups -bdu AB12CD23 -s2b Share1,Share2
EOH
}

function main() {
    if [ "$#" -eq 0 ]; then
        printHelp
        exit 100
    fi

    local vmName
    vmName="$(parseVmName "$@" || (printHelp && exit 101))"
    readonly vmName

    local backupDeviceUuid
    backupDeviceUuid="$(parseBackupDeviceUuid "$@" || (printHelp && exit 102))"
    readonly backupDeviceUuid

    local sharesToBackup
    sharesToBackup="$(parseSharesToBackup "$@" || (printHelp && exit 103))"
    readonly sharesToBackup

    local -r backupMountDir="/mnt/backup-$backupDeviceUuid"

    logInfo "VM Name: $vmName"
    logInfo "Backup device UUID: $backupDeviceUuid"
    logInfo "Shares to backup: $sharesToBackup"

    shutdownVm "$vmName" || exit 10
    mountBackup "$backupDeviceUuid" "$backupMountDir" || exit 11
    performBackup "$backupMountDir" "$sharesToBackup" || exit 12
    umountBackup "$backupMountDir" || exit 13
    startVm "$vmName" || exit 14
}

main "$@"
