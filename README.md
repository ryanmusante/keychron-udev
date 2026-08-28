# keychron-udev

Version 1.0.0 (2026-08-26). Script: `keychron-udev.fish`.
udev access for Keychron Launcher on Linux, done the systemd way.

## Overview

Keychron's web configurator at `launcher.keychron.com` talks to the board over
WebHID, and its firmware flasher talks to the board's STM32 DFU bootloader over
WebUSB. Both need the browser to open a device node that Linux creates as
`root:root`: `/dev/hidrawN` for the board (mode 0600) and `/dev/bus/usb/BBB/DDD`
for the bootloader (mode 0664). Without a rule the Launcher stops at
"HID device connected" and a flash stalls at 0 %.

`keychron-udev.fish` installs one rule file, `/etc/udev/rules.d/70-keychron.rules`,
that tags both device classes `uaccess`, so systemd-logind hands the logged-in
seat user a dynamic ACL. No `input` or `plugdev` group, no `MODE="0666"`, no
per-user `GROUP=`. Before it writes anything it proves the candidate with
`udevadm test -D`, then it writes atomically, reloads udev, re-adds the live
nodes so the ACL lands without a replug, and verifies read-write access as the
invoking user.

## Requirements

| Component  | Requirement                                   | Notes                                                        |
|------------|-----------------------------------------------|--------------------------------------------------------------|
| OS         | Arch-based distro with systemd-udev >= 258    | `udevadm test -D` was added in 258; developed against 261    |
| Shell      | fish >= 3.6                                   | newest features used: `string match -g` (3.4), `string split -f` and `string pad` (3.2) |
| Privileges | sudo for `--install` only                     | `--check` and `--verify` never elevate                       |
| Tools      | coreutils                                     | `id`, `install`, `mv -T`, `cp`, `rm`, `mkdir`, `mktemp`, `sha256sum`, `date`, `touch`, `chmod` |
| Optional   | diffutils, acl                                | diff display; `getfacl` ACL display (acl is a systemd dep)   |
| Browser    | native Chrome, Chromium or Edge               | WebHID and WebUSB; Snap and Flatpak sandboxes need device access |
| Keyboard   | any Launcher board or receiver, VID `3434`    | QMK-based HE and Max boards flash through the STM32 DFU bootloader; ZMK-based Ultra boards are not verified |

## Quick Start

```fish
chmod 0755 keychron-udev.fish
./keychron-udev.fish --check
./keychron-udev.fish --install
```

Put the board on the cable with its side toggle on Cable before `--install`, so
the dry-run has a real hidraw node to prove the rule against. Then open
`https://launcher.keychron.com/` in Chrome, Connect, and use Firmware Update.

> [!CAUTION]
> A flash runs on the board's bootloader over a direct USB port. Do not unplug
> the cable or put a second Keychron board into bootloader mode at the same
> time; two "STM32 BOOTLOADER" entries in the WebUSB chooser differ only by
> serial number.

## Modes

| Flag              | Action                                                                                        | Elevates |
|-------------------|-----------------------------------------------------------------------------------------------|----------|
| `-c`, `--check`   | default; list Keychron USB devices, a board sitting in DFU bootloader mode, and USB-bus hidraw nodes, compare the installed rule; no system change | no       |
| `-i`, `--install` | dry-run, back up and diff an existing file, write, reload, re-add live nodes, verify          | sudo     |
| `-v`, `--verify`  | confirm read-write access for the current user on every Keychron hidraw node and DFU device  | no       |
| `-h`, `--help`    | usage                                                                                         | no       |
| `-V`, `--version` | version                                                                                       | no       |

All diagnostics go to stderr; stdout carries only `--help` and `--version`.
The run log opens after preflight, so every line of a `--check`, `--install` or
`--verify` run is mirrored to it with a timestamp and the log path is printed as
the last line; `--help`, `--version`, a usage error and a preflight failure all
exit before the log exists and are never written to it. Color is used only on a
terminal and is disabled by a non-empty `NO_COLOR` or by `TERM=dumb`.

## Files

| Path                                                     | Purpose                                   | Mode      |
|----------------------------------------------------------|-------------------------------------------|-----------|
| `/etc/udev/rules.d/70-keychron.rules`                    | the installed rule                        | 0644 root |
| `$XDG_STATE_HOME/keychron-udev/keychron-udev.log`        | append-only run log, one line per message | 0600      |
| `$XDG_STATE_HOME/keychron-udev/<timestamp>-70-keychron.rules.bak` | backup of a replaced rule file   | 0644      |
| `$XDG_RUNTIME_DIR/keychron-udev.lock`                    | lock directory held during `--install`    | dir       |
| `/etc/udev/rules.d/70-keychron.rules.tmp`                | write staging; removed on failure and cleared on the next `--install` | 0644 root |

`XDG_STATE_HOME` defaults to `~/.local/state`; `XDG_RUNTIME_DIR` falls back to
`/tmp`. The state directory is created 0700.

## Exit Codes

| Code | Meaning                                                              |
|------|----------------------------------------------------------------------|
| 0    | ok                                                                   |
| 1    | error: dry-run, backup, write, reload, trigger or lock failure       |
| 2    | usage error, or run as root                                          |
| 3    | preflight: missing `id`, `udevadm`, `sudo`, USB sysfs or rules dir; udev < 258; sudo authentication failed |
| 4    | drift (`--check`): rule file missing, unreadable, not a regular file, or differing from the expected text |
| 5    | verify failed: a node is not readable and writable for the user      |
| 129, 130, 143 | SIGHUP, SIGINT, SIGTERM after cleanup                       |

## The Rule

```
# 70-keychron.rules: written by keychron-udev.fish. Keep the number below 73:
# 73-seat-late.rules is what turns the uaccess tag into an ACL.
# Keychron Launcher (WebHID): raw HID on Keychron USB devices, including the 2.4 GHz Link receiver
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", TAG+="uaccess"
# Launcher firmware flash (WebUSB): STM32 ROM DFU bootloader the board re-enumerates as
SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", TAG+="uaccess"
```

> [!WARNING]
> The file number is load-bearing. `73-seat-late.rules` is the rule that runs the
> `uaccess` builtin for tagged devices, and it only sees tags added by files that
> sort before it. A `99-keychron.rules` with `TAG+="uaccess"` alone does nothing;
> the popular 99-numbered guides work only because they also set `GROUP=` to the
> user or add the user to `input`.

Line 1 covers every Keychron HID interface on the USB bus, including the
2.4 GHz Link receiver (`3434:d030`), so the Launcher can also configure a board
over 2.4 GHz once the receiver runs firmware d.3.0/c.3.0 or later. It sets no
`MODE=`: the node stays `0600 root:root` and the `uaccess` ACL is the only thing
that grants access, which is the point. Line 2 matches the same `0483:df11` pair
that systemd's hwdb names "STM Device in DFU Mode" and that the Arch `dfu-util`
package covers in `/usr/lib/udev/rules.d/60-dfuse.rules`; it carries no
`ACTION==` qualifier, so a synthetic re-add or change event applies it too.
Bluetooth-attached boards carry no `idVendor` attribute and are never matched;
the Launcher needs the cable or the receiver anyway.

## What `--install` Does

1. Refuses to run as root, checks `id`, `udevadm`, `sudo`, USB sysfs, the rules
   directory and `73-seat-late.rules`, and requires systemd-udev 258 or later.
2. Takes a lock directory under `XDG_RUNTIME_DIR` and authenticates once with
   `sudo -v`.
3. Writes the candidate rule to a private temp directory and runs
   `sudo udevadm test --json=short -D <tmp> /dev/hidrawN` for every Keychron
   hidraw node. The JSON must list `uaccess` under `tags` and a queued builtin
   `uaccess` under `queuedCommands`; the second condition is the proof that the
   file sorts before `73-seat-late.rules`. Any failure aborts before a write.
4. Removes a stale `70-keychron.rules.tmp` if one is present. udev only reads
   `*.rules`, so a `.tmp` left behind by a run killed between staging and rename
   is inert, but it is cleared before anything else happens.
5. If an identical `70-keychron.rules` is already installed, leaves it
   untouched. If a different one exists, copies it to
   `$XDG_STATE_HOME/keychron-udev/<timestamp>-70-keychron.rules.bak` and prints
   a unified diff of that copy against the new text. A rule file the invoking
   user cannot read is copied with `sudo install -m 0600 -o <uid> -g <gid>`
   instead, so the backup is preserved and readable; anything that cannot be
   copied at all (a directory at that path, for instance) aborts before a write.
6. Installs the file as `70-keychron.rules.tmp` (0644) and renames it into
   place with `mv -T`, so udev never reads a partial file; a failed write
   removes the temporary file again.
7. Runs `sudo udevadm control --reload`, then
   `sudo udevadm trigger --action=add --settle` on the live hidraw nodes, which
   applies the ACL without unplugging.
8. Runs the same checks as `--verify`, which also prints the `user:` ACL entry
   of every node when `getfacl` is installed.

## Verification

```fish
fish --no-execute keychron-udev.fish        # authoritative syntax gate
fish_indent --check keychron-udev.fish      # 0-diff on the shipped file
./keychron-udev.fish --check
./keychron-udev.fish --verify
sudo udevadm test --json=pretty /dev/hidrawN 2>/dev/null | jq '.tags, .queuedCommands'
getfacl -p /dev/hidrawN
command sha256sum keychron-udev.fish
```

`jq` is optional; the raw JSON is readable as is. The run log keeps every
line of every run for later comparison. In Chrome, `chrome://device-log` lists
every HID and USB access attempt with its error.

## Uninstall

```fish
sudo rm /etc/udev/rules.d/70-keychron.rules
sudo udevadm control --reload
```

Existing device nodes keep their ACL until they are re-added; unplug and replug
the board, or reboot. Backups and the run log in `$XDG_STATE_HOME/keychron-udev` are yours to
delete.

## Troubleshooting

**The Launcher says "HID device connected" and stops.** The browser could not
open `/dev/hidrawN`. Run `./keychron-udev.fish --verify`; a FAIL line names the
node. Re-run `--install`, or unplug and replug the board so the ACL is applied.

**The flash stalls at 0 %.** The WebUSB chooser needs the DFU node. Confirm the
board re-enumerated as `0483:df11` (`lsusb -d 0483:df11` with usbutils
installed, or `--verify` while the board sits in bootloader mode) and that the
browser is a native package, not a Snap or Flatpak.

**Chrome is a Flatpak.** Grant it the device nodes:
`flatpak override --user --device=all com.google.Chrome`. Snap Chromium is
sandboxed as well; the published reports resolved it with the native package.

**The board is in Bluetooth mode.** Switch the side toggle to Cable (or 2.4 GHz
with the receiver plugged in). Bluetooth HID is never matched and a flash needs
the cable regardless.

**The dry-run fails with "no uaccess builtin queued".** Another rules file or a
changed systemd layout is preventing `73-seat-late.rules` from seeing the tag.
Check `ls /usr/lib/udev/rules.d/73-seat-late.rules` and any local override in
`/etc/udev/rules.d/`.

**Verification fails in an SSH session.** The `uaccess` ACL is granted to the user
of the active local seat session, so run the script from the desktop session
that will also run Chrome.

**Install reports that another run holds the lock.** A previous run was killed
before its cleanup. If no other run is active, remove the directory:
`rmdir $XDG_RUNTIME_DIR/keychron-udev.lock`.

**The receiver's own firmware needs updating.** For keyboard receivers Keychron
ships that path only as a Windows updater; it is outside what a browser can do.
Board firmware and Launcher configuration are unaffected.

## Security Notes

`_sha` and `_diff` invoke `command sha256sum` and `command diff` rather than the
bare names. fish autoloads `/usr/share/fish/functions/diff.fish`, which wraps
`diff` with `--color=auto`, and any user function or alias of either name would
otherwise sit between you and the decision to overwrite a system rule file.

Line 1 grants the seat user read-write access to every Keychron HID interface,
not only the raw-HID interface the Launcher uses. On a single-user desktop that
is the accepted trade-off; scoping to the raw interface would need a report
descriptor check like the `qmk_id` helper in the `qmk` package. The rule never
touches non-Keychron devices, never uses world-writable modes, and logind
removes the ACL again when the session stops being the active one.

## Testing

The four filesystem roots (`SYSFS`, `DEVFS`, `RULES_DIR`, `SEAT_LATE`) are fixed
`set -g` lines with no environment override, so nothing in the environment can
redirect a privileged write. A test kit repoints them with a four-line patch:

```fish
sed -e "s#^set -g SYSFS /sys\$#set -g SYSFS $KIT/sys#" \
    -e "s#^set -g DEVFS /dev\$#set -g DEVFS $KIT/dev#" \
    -e "s#^set -g RULES_DIR /etc/udev/rules.d\$#set -g RULES_DIR $KIT/etc/udev/rules.d#" \
    -e "s#^set -g SEAT_LATE /usr/lib/udev/rules.d/73-seat-late.rules\$#set -g SEAT_LATE $KIT/usr/lib/udev/rules.d/73-seat-late.rules#" \
    keychron-udev.fish > $KIT/keychron-udev.fish
```

The script was certified in a stub-kit as an unprivileged user: a fake sysfs with
a K2 HE on two hidraw nodes, a Link receiver, an STM32 DFU device, a
Bluetooth-bus Keychron node and a Logitech node as negative controls, and stub
`sudo`/`udevadm` binaries that log every invocation. Covered: device listing,
`--check` before and after install, tamper detection with diff, reinstall with
backup, the three dry-run failure paths (no JSON, no tag, no queued builtin),
verify denial, lock contention, the preflight gates (including a missing `id`
and a missing `udevadm`), root refusal, argparse errors, SIGPIPE on `--help`,
the color gate on a pty across `NO_COLOR` unset, empty and non-empty, a write
failure that leaves no `.tmp` behind, a stale `.tmp` on both the rewrite and the
already-current path, an installed rule that is unreadable to the invoking user
and one replaced by a directory, a leading-zero `busnum`/`devnum`, a user
`diff`/`sha256sum` function in `conf.d` that must not reach the script, `|` in
sysfs strings, empty `XDG_*` variables, the run-log mirror (0600, header line
per run), and SIGINT/SIGTERM/SIGHUP during `sudo -v` (exit 130/143/129, nothing
written, lock and temp removed). The privileged path is exercised for real: the
kit's `sudo` stand-in is a setuid-root helper, not a pass-through, so the
backup, staging and rename run with the privileges they will have on the
host.
The privileged command sequence recorded by the stubs is: `sudo -v`, one
`udevadm test --json=short -D` per node, `install -m 0644` to `.tmp`, `mv -T`,
`udevadm control --reload`, `udevadm trigger --action=add --settle`. Two calls
appear only when their condition is met: `rm -f` on a stale `.tmp`, and
`install -m 0600 -o <uid> -g <gid>` when the installed rule cannot be read by
the invoking user. Nothing else is ever run through `sudo`.

## Sources

- systemd `rules.d/73-seat-late.rules.in`: `TAG=="uaccess|xaccess-*", ENV{MAJOR}!="", RUN{builtin}+="uaccess"`
  ([github](https://github.com/systemd/systemd/blob/main/rules.d/73-seat-late.rules.in)).
- systemd `rules.d/70-uaccess.rules.in`: upstream precedent for `uaccess` on `hidraw`
  ([github](https://github.com/systemd/systemd/blob/main/rules.d/70-uaccess.rules.in)).
- systemd `src/udev/udev-dump.c`: JSON keys `tags`, `currentTags`, `queuedCommands`
  ([github](https://github.com/systemd/systemd/blob/main/src/udev/udev-dump.c)).
- udevadm(8), systemd 261.2: `test` accepts `/dev/` paths, `--json=`, `-D` (added in 258),
  `control --reload`, `trigger --action= --settle` ([man.archlinux.org](https://man.archlinux.org/man/udevadm.8)).
- udev(7): `ATTRS{}` searches the devpath upwards ([man.archlinux.org](https://man.archlinux.org/man/udev.7)).
- Arch Wiki, Udev, "Allowing regular users to use devices": file must lexically precede
  `73-seat-late.rules` ([wiki.archlinux.org](https://wiki.archlinux.org/title/Udev)).
- systemd hwdb `20-usb-vendor-model.hwdb`: `usb:v0483pDF11*` is "STM Device in DFU Mode"
  ([github](https://github.com/systemd/systemd/blob/main/hwdb.d/20-usb-vendor-model.hwdb)).
- Arch `extra/dfu-util 0.11-3`, `/usr/lib/udev/rules.d/60-dfuse.rules`: the same STM32 line
  ([archlinux.org](https://archlinux.org/packages/extra/x86_64/dfu-util/)).
- Linux `drivers/hid/hid-core.c` and `drivers/hid/hidraw.c`: `HID_ID`/`HID_NAME` uevent keys
  and the hidraw class device's HID parent ([github](https://github.com/torvalds/linux/tree/master/drivers/hid)).
- Keychron, "How to Restore Factory Settings and Update Firmware on Launcher": the DFU chooser
  ([keychron.com](https://www.keychron.com/pages/how-to-factory-reset-or-use-the-launcher-web-app-to-flash-firmware-for-your-keyboard)).
- Keychron, "How to Flash the Firmware for the Keychron Receiver": Launcher over 2.4 GHz from d.3.0/c.3.0
  ([keychron.com](https://www.keychron.com/pages/how-to-flash-the-firmware-for-the-keychron-receiver)).
- fish CHANGELOG: `string match --groups-only` (3.4.0), `string split --fields` and
  `string pad` (3.2.0) ([github](https://github.com/fish-shell/fish-shell/blob/master/CHANGELOG.rst)).
- fish `share/functions/diff.fish`: fish autoloads a `diff` function that adds `--color=auto`,
  which is why `_diff` calls `command diff`
  ([github](https://github.com/fish-shell/fish-shell/blob/master/share/functions/diff.fish)).
- systemd `src/udev/udev-rules.c`, `udev_rules_load()`: a `-D` directory is prepended to the
  rules-directory list and every file is then sorted by basename, so a `70-` candidate in the
  temp dir both precedes `73-seat-late.rules` and masks an installed file of the same name
  ([github](https://github.com/systemd/systemd/blob/main/src/udev/udev-rules.c)).

