# Unraid-utils
--------------

This package has assorted scripts to perform common operations on an Unraid server.

## Running Shellcheck

Run `./shellcheck.sh` to run shellcheck against the commited scripts that require shellcheck.

## Backup script

```text
Usage: backup.sh [OPTIONS]

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
  # backup.sh -vm Backups -bdu AB12CD23 -s2b Share1,Share2
```
