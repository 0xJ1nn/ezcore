# Where saves are backed up

Saves always live in the app's own local vault first. When a suitable folder
is available, the app also mirrors saves there so a copy exists outside that
vault. Mirroring is a local file copy: the app does not upload anything, does
not sync between devices, and does not reconcile versions across machines.
Any synchronization of a folder is done by the storage provider that owns it,
not by ezCORE.

The durability outcome is the same on all five targets: saves survive app
deletion only where the probe verified a durable location outside the app's
private data. The provider that supplies that location differs by OS, because
each OS exposes writable storage in its own way. The difference is in the path
and the picker, not in what a save is promised to survive.

## Where the mirror goes

| Platform | Folder | How it is chosen |
| --- | --- | --- |
| Android | A folder picked with the system folder picker | Storage Access Framework tree grant, remembered after the first choice |
| iOS | `Documents/ezCORE Backup` inside the app's iCloud container | Native channel, when the iCloud capability is enabled |
| macOS | `Documents/ezCORE Backup` inside the app's iCloud container | Same channel as iOS, with the same requirement |
| Windows | `ezCORE` inside the OneDrive folder | Environment variable set by the OneDrive client; the folder must already exist |
| Linux | `ezCORE-backup` under `$XDG_DATA_HOME`, or `~/.local/share/ezCORE-backup` | Filesystem location derived from the environment |

Every candidate is probed before use. Where the OS permits it, the app creates
the folder when missing, writes a throwaway file, and deletes that file again.
On Windows the `ezCORE` folder inside OneDrive must already exist: when it is
missing, the app reports the backup as unavailable rather than creating it. A
folder that cannot take the probe is never presented as a backup location; the
app keeps using local saves
and shows the reason in Storage. The probe is only a check at the moment the
folder is chosen: if the folder is later deleted or becomes unwritable, the
next save reports that failure and Storage changes to Unavailable with the
reason. The app never continues to claim a working backup after such a failure.

Only saves are mirrored. Settings, the game library and core choices are kept
in the app's own data and are not copied to the backup folder; deleting the app
removes them. Saving a game again after reinstalling restores the save bytes,
not those preferences.

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

**Verified** means the host answered the platform channel where one is used,
the location was written and probed successfully, and the probed folder is
outside the app's private data, so saves placed there survive app removal. On
Android this also means the tree grant was persisted rather than refused by
the platform. On Apple platforms the iCloud container had to exist and be
writable. On desktop the chosen folder had to pass the same write-and-delete
probe. The badge promises that durability on that device; it does not promise
cloud sync or a version history.

**Best effort** means a writable folder was found, but it lives inside the
app's own data and is deleted when the app is deleted. On iOS and macOS this
is the `ezCORE Backup` folder under the app's Documents directory, used when
no iCloud container is available; Storage labels the provider `Documents`.
The app still writes saves there, but the badge makes the missing durability
visible instead of promising it. When the iCloud check itself fails, the
reason says so rather than claiming iCloud is simply not set up.

**Unavailable** means no usable folder was found. Saves stay in the local
vault. The text under the badge states why.

## What counts as a save in the backup folder

Saves are listed from the backup's own index, not from every file that happens
to sit in the chosen folder. Notes, ROMs and other apps' files in the same
folder are never offered for restore. A file without an index entry is not a
save ezCORE can vouch for.

When two devices use one folder, each install keeps its own index entry for a
slot. Deleting a save on one device does not hide the other device's copy. The
bytes of one file are still last-writer-wins: ezCORE does not merge or compare
versions from different machines.

## When the app is removed

A save survives removal only where the verified folder is still present and
the app can reach it again. That outcome is the same on every target; the
provider that holds the folder is what changes.

- **Android:** files in the granted tree remain where they were written. The
  permission is tied to the installation, so a reinstall must choose the
  folder again before the app can reach those files.
- **iOS and macOS with iCloud:** files remain in the app's iCloud container.
  A reinstall using the same bundle identifier can reach them again.
- **iOS and macOS with the Documents fallback:** the folder is inside the
  app's sandbox and is removed with the app. These saves are best effort, not
  verified.
- **Windows:** the `ezCORE` folder inside OneDrive remains on disk, provided
  it existed for the probe. Whether OneDrive syncs it off the machine is decided
  by the client, not by ezCORE.
- **Linux:** the `ezCORE-backup` folder under the XDG data directory remains
  on disk.

## Maintainer step for iCloud

The iCloud container is not available by default. The app's bundle identifier
must have the iCloud capability with a ubiquity container enabled in the
developer portal, and the matching entitlements and provisioning profile must
be included when the app is signed. Without that setup the native handler
returns no container, and the app uses the best-effort Documents fallback
described above. No entitlement is added by the backup code itself, so an app
signed without the capability keeps working with the fallback rather than
failing to launch.
