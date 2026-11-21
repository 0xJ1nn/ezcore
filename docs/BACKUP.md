# Where saves are backed up

Saves always live in the app's own local vault first. When a suitable folder
is available, the app also mirrors saves there so a copy exists outside that
vault. Mirroring is a local file copy: the app does not upload anything, does
not sync between devices, and does not reconcile versions across machines.
Any synchronization of a folder is done by the storage provider that owns it,
not by ezCORE.

## Where the mirror goes

| Platform | Folder | How it is chosen |
| --- | --- | --- |
| Android | A folder picked with the system folder picker | Storage Access Framework tree grant, remembered after the first choice |
| iOS | `Documents/ezCORE Backup` inside the app's iCloud container | Native channel, when the iCloud capability is enabled |
| macOS | `Documents/ezCORE Backup` inside the app's iCloud container | Same channel as iOS, with the same requirement |
| Windows | `ezCORE` inside the OneDrive folder | Environment variable set by the OneDrive client; the folder must already exist |
| Linux | `ezCORE-backup` under `$XDG_DATA_HOME`, or `~/.local/share/ezCORE-backup` | Filesystem location derived from the environment |

Every candidate is probed before use: the app creates it when missing, writes
a throwaway file, and deletes that file again. A folder that cannot take the
probe is never presented as a backup location; the app keeps using local saves
and shows the reason in Storage.

## Why a phone asks for a folder once

Android does not let an app write to arbitrary folders on shared storage. The
system folder picker is the way a person grants that right: choosing a folder
hands the app a tree URI and permission to read and write inside it. The app
asks for that permission to be persisted, so the choice survives a reboot and
does not need repeating on every launch.

A granted folder can stop working. If the permission is revoked in Android
settings, or the folder is moved or deleted, the probe fails and the app
reports the backup as unavailable. Choosing the folder again restores it.

## Verified and Best effort in Storage

The badge in Settings → Storage describes how much the app can trust the
folder, not how full the backup is.

**Verified** means the host answered the platform channel, the location was
written and probed successfully, and the folder is expected to remain after
the app is removed. On Android this also means the tree grant was persisted
rather than refused by the platform. On Apple platforms the iCloud container
had to exist and be writable. On desktop the chosen folder had to pass the
same write-and-delete probe.

**Best effort** means a writable folder was found, but it lives inside the
app's own data and is deleted when the app is deleted. On iOS and macOS this
is the `ezCORE Backup` folder under the app's Documents directory, used when
no iCloud container is available. The app still writes saves there, but the
badge makes the missing durability visible instead of promising it.

**Unavailable** means no usable folder was found. Saves stay in the local
vault. The text under the badge states why.

## When the app is removed

What survives removal depends on the folder.

- **Android:** files in the granted tree remain where they were written. The
  permission is tied to the installation, so a reinstall must choose the
  folder again before the app can reach those files.
- **iOS and macOS with iCloud:** files remain in the app's iCloud container.
  A reinstall using the same bundle identifier can reach them again.
- **iOS and macOS with the Documents fallback:** the folder is inside the
  app's sandbox and is removed with the app.
- **Windows and Linux:** the folder is outside the app's private data and
  remains on disk. On Windows, whether it leaves the machine is decided by
  the OneDrive client, not by ezCORE.

## Maintainer step for iCloud

The iCloud container is not available by default. The app's bundle identifier
must have the iCloud capability with a ubiquity container enabled in the
developer portal, and the matching entitlements and provisioning profile must
be included when the app is signed. Without that setup the native handler
returns no container, and the app uses the best-effort Documents fallback
described above. No entitlement is added by the backup code itself, so an app
signed without the capability keeps working with the fallback rather than
failing to launch.
