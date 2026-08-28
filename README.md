# keychron-udev

Version 1.0.0 (2026-08-26). Script: `keychron-udev.fish`.

udev access for Keychron Launcher on Linux.

## Overview

Keychron Launcher talks to the board over WebHID and to its STM32 DFU bootloader
over WebUSB. Both need the browser to open a node Linux creates `root:root`:
`/dev/hidrawN` (0600) and `/dev/bus/usb/BBB/DDD` (0664). Without a rule the
Launcher stops at "HID device connected" and a flash stalls at 0 %.

`keychron-udev.fish` installs `/etc/udev/rules.d/70-keychron.rules`, tagging both
device classes `uaccess` so systemd-logind grants the active seat user a dynamic
ACL. No `input` or `plugdev` group, no `MODE="0666"`, no per-user `GROUP=`.

## Requirements

| Component  | Requirement                                | Notes |
|------------|--------------------------------------------|-------|
| OS         | Arch-based distro, systemd-udev >= 258     | `udevadm test -D` added in 258; developed against 261 |
| Shell      | fish >= 3.6                                | newest features used: `string match -g` (3.4), `string split -f` and `string pad` (3.2) |
| Privileges | sudo for `--install` only                  | `--check` and `--verify` never elevate |
| Tools      | coreutils                                  | `id`, `install`, `mv -T`, `rm`, `rmdir`, `mkdir`, `mktemp`, `sha256sum`, `cat`, `dirname`, `date`, `touch`, `chmod` |
| Optional   | diffutils, acl                             | diff display; `getfacl` ACL display |
| Browser    | native Chrome, Chromium or Edge            | Snap and Flatpak sandboxes need device access granted separately |
| Keyboard   | any Launcher board or receiver, VID `3434` | QMK-based HE and Max boards flash through the STM32 DFU bootloader; ZMK-based Ultra boards unverified |

## Quick Start

```fish
chmod 0755 keychron-udev.fish
./keychron-udev.fish --check
./keychron-udev.fish --install
```

Put the board on the cable with its side toggle on Cable first, so the dry-run
has a real hidraw node to prove against. Then open `https://launcher.keychron.com/`
in Chrome, Connect, and use Firmware Update.

> [!CAUTION]
> Do not unplug the cable during a flash, and do not put a second Keychron board
> into bootloader mode at the same time: two "STM32 BOOTLOADER" entries in the
> WebUSB chooser differ only by serial number.

## Modes

| Flag | Action | Elevates |
|------|--------|----------|
| `-c`, `--check`   | default; list Keychron devices, a board in DFU mode and USB-bus hidraw nodes, compare the installed rule | no |
| `-i`, `--install` | dry-run, back up and diff an existing file, write, reload, re-add live nodes, verify | sudo |
| `-v`, `--verify`  | confirm read-write access on every Keychron hidraw node and DFU device | no |
| `-h`, `--help`    | usage | no |
| `-V`, `--version` | version | no |

Diagnostics go to stderr; stdout carries only `--help` and `--version`. The run
log opens after preflight: every line of a `--check`, `--install` or `--verify`
run is mirrored to it with a timestamp, and the path is printed last. `--help`,
`--version`, usage errors and preflight failures exit before the log exists; a
failed `sudo -v` (also rc 3) comes after it opens.
Color requires a terminal and is disabled by a non-empty `NO_COLOR` or
`TERM=dumb`.

## Files

| Path | Purpose | Mode |
|------|---------|------|
| `/etc/udev/rules.d/70-keychron.rules` | the installed rule | 0644 root |
| `/etc/udev/rules.d/70-keychron.rules.tmp` | write staging; inert to udev, which reads only `*.rules`; removed on failure, cleared on the next `--install` | 0644 root |
| `$XDG_STATE_HOME/keychron-udev/keychron-udev.log` | append-only run log | 0600 |
| `$XDG_STATE_HOME/keychron-udev/<timestamp>-70-keychron.rules.bak` | backup of a replaced rule | 0644 (0600 via sudo) |
| `$XDG_RUNTIME_DIR/keychron-udev.lock` | lock held during `--install` | dir |

`XDG_STATE_HOME` defaults to `~/.local/state`; `XDG_RUNTIME_DIR` falls back to
`/tmp`. The state directory is created 0700.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | ok |
| 1 | error: dry-run, backup, write, reload, trigger or lock failure |
| 2 | usage error, or run as root |
| 3 | preflight: missing `id`, `udevadm`, `sudo`, USB sysfs or rules dir; udev < 258; sudo authentication failed |
| 4 | drift (`--check`): rule missing, unreadable, not a regular file, or differing from the expected text |
| 5 | verify failed: a node is not readable and writable for the user |
| 129, 130, 143 | SIGHUP, SIGINT, SIGTERM after cleanup |

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
> The file number is load-bearing. `73-seat-late.rules` runs the `uaccess`
> builtin, and it only sees tags added by files that sort before it. A
> `99-keychron.rules` with `TAG+="uaccess"` alone does nothing; the popular
> 99-numbered guides work only because they also set `GROUP=` or add the user to
> `input`.

Line 1 covers every Keychron HID interface on the USB bus, including the
2.4 GHz Link receiver (`3434:d030`); the Launcher can configure a board over
2.4 GHz once the receiver runs firmware d.3.0/c.3.0 or later. It sets no `MODE=`:
the node stays `0600 root:root` and the ACL is the only grant. Line 2 matches the
`0483:df11` pair systemd's hwdb names "STM Device in DFU Mode" and that Arch's
`dfu-util` covers in `/usr/lib/udev/rules.d/60-dfuse.rules`; it carries no
`ACTION==` qualifier, so a synthetic re-add or change event applies it too.
Bluetooth-attached boards expose no `idVendor` attribute and are never matched.

## What `--install` Does

1. Refuses root; checks `id`, `udevadm`, `sudo`, USB sysfs, the rules directory
   and `73-seat-late.rules`; requires systemd-udev 258 or later.
2. Takes a lock directory under `XDG_RUNTIME_DIR`, authenticates with `sudo -v`.
3. Writes the candidate to a private temp directory and runs
   `sudo udevadm test --json=short -D <tmp> <node>` per live hidraw node and
   STM32 DFU device. The JSON must list `uaccess` under `tags` and a queued
   `uaccess` builtin under `queuedCommands` — the second is the proof the file
   sorts before `73-seat-late.rules`. Any failure aborts before a write.
4. Removes a stale `70-keychron.rules.tmp`.
5. Leaves an identical rule untouched. Copies a differing one (0644) to
   `$XDG_STATE_HOME/keychron-udev/<timestamp>-70-keychron.rules.bak` and diffs
   that copy against the new text. A rule the invoking user cannot read is copied
   with `sudo install -m 0600 -o <uid> -g <gid>`; anything that cannot be copied
   at all aborts before a write.
6. Installs to `70-keychron.rules.tmp` (0644) and renames with `mv -T`, so udev
   never reads a partial file; a failed write removes the temporary file.
7. Runs `sudo udevadm control --reload`, then
   `sudo udevadm trigger --action=add --settle` on the live hidraw nodes and
   DFU devices, so a board already sitting in the bootloader gets its ACL
   without a replug.
8. Runs the `--verify` checks, printing each node's `user:` ACL entry when
   `getfacl` is installed.

## Verification

```fish
fish --no-execute keychron-udev.fish        # syntax gate
fish_indent --check keychron-udev.fish      # 0-diff on the shipped file
./keychron-udev.fish --check
./keychron-udev.fish --verify
sudo udevadm test --json=pretty /dev/hidrawN 2>/dev/null | jq '.tags, .queuedCommands'
getfacl -p /dev/hidrawN
command sha256sum keychron-udev.fish
```

`jq` is optional. In Chrome, `chrome://device-log` lists every HID and USB access
attempt with its error.

## Uninstall

```fish
sudo rm /etc/udev/rules.d/70-keychron.rules
sudo udevadm control --reload
```

Existing nodes keep their ACL until re-added: replug the board or reboot.

## Troubleshooting

**Launcher says "HID device connected" and stops.** The browser could not open
`/dev/hidrawN`. Run `--verify`; a FAIL line names the node. Re-run `--install`,
or replug the board.

**Flash stalls at 0 %.** The WebUSB chooser needs the DFU node. Confirm the board
re-enumerated as `0483:df11` (`lsusb -d 0483:df11`, or `--verify` while it sits
in bootloader mode) and that the browser is a native package.

**Chrome is a Flatpak.** `flatpak override --user --device=all com.google.Chrome`.
Snap Chromium is sandboxed as well.

**Board is in Bluetooth mode.** Switch the toggle to Cable, or to 2.4 GHz with
the receiver plugged in.

**Dry-run fails with "no uaccess builtin".** Something is stopping
`73-seat-late.rules` from seeing the tag. Check
`ls /usr/lib/udev/rules.d/73-seat-late.rules` and any override in
`/etc/udev/rules.d/`.

**Verification fails over SSH.** The ACL goes to the active local seat session.
Run the script from the desktop session that will run Chrome.

**"another run holds the lock".** A previous run was killed before cleanup.
`rmdir $XDG_RUNTIME_DIR/keychron-udev.lock`.

**The receiver's own firmware needs updating.** Keychron ships that path only as
a Windows updater. Board firmware and Launcher configuration are unaffected.

## Security Notes

Line 1 grants the seat user read-write access to every Keychron HID interface,
not only the raw-HID interface the Launcher uses. On a single-user desktop that
is the accepted trade-off; scoping to the raw interface would need a report
descriptor check like the `qmk_id` helper in the `qmk` package. The rule never
touches non-Keychron devices, never uses world-writable modes, and logind removes
the ACL when the session stops being active.

`_sha` and `_diff` call `command sha256sum` and `command diff`. fish autoloads
`share/functions/diff.fish`, which wraps `diff` with `--color=auto`; a user
function of either name would otherwise sit between the operator and the decision
to overwrite a system rule file.

`SYSFS`, `DEVFS`, `RULES_DIR` and `SEAT_LATE` are fixed `set -g` lines with no
environment override, so nothing in the environment can redirect a privileged
write.

## Testing

Certified in a stub kit as an unprivileged user against a fake sysfs: a K2 HE on
two hidraw nodes, a Link receiver, an STM32 DFU device, and a Bluetooth-bus
Keychron node plus a Logitech node as negative controls. The kit's `sudo` is a
setuid-root helper, not a pass-through, so the privileged path runs for real. It
repoints the four roots with a four-line patch:

```fish
sed -e "s#^set -g SYSFS /sys\$#set -g SYSFS $KIT/sys#" \
    -e "s#^set -g DEVFS /dev\$#set -g DEVFS $KIT/dev#" \
    -e "s#^set -g RULES_DIR /etc/udev/rules.d\$#set -g RULES_DIR $KIT/etc/udev/rules.d#" \
    -e "s#^set -g SEAT_LATE /usr/lib/udev/rules.d/73-seat-late.rules\$#set -g SEAT_LATE $KIT/usr/lib/udev/rules.d/73-seat-late.rules#" \
    keychron-udev.fish > $KIT/keychron-udev.fish
```

Covered:

- device listing; `--check` before, after and against a tampered rule
- reinstall with backup and diff; an installed rule unreadable to the invoking
  user; a directory at the rule path
- the three dry-run failure paths: no JSON, no tag, no queued builtin
- reload, trigger and write failures; a stale `.tmp` on both the rewrite and the
  already-current path
- preflight gates including missing `id` and missing `udevadm`; root refusal;
  argparse errors; the udev 257/258 boundary
- verify denial; a leading-zero `busnum`/`devnum`; `|` in sysfs strings; empty
  `XDG_*` variables
- `--install` with a board sitting in the bootloader: the DFU node is dry-run,
  triggered and verified
- a passing `--verify` with `getfacl` installed and a node without a named
  `user:` entry (exit stays 0); a backup written under `umask 077` (still 0644)
- lock contention; SIGPIPE on `--help`; SIGINT/SIGTERM/SIGHUP during `sudo -v`
  (130/143/129, nothing written, lock and temp removed)
- the color gate on a pty across `NO_COLOR` unset, empty and non-empty
- a user `diff`/`sha256sum` function in `conf.d` that must not reach the script
- the run-log mirror (0600, one header line per run)

Privileged calls recorded by the stubs: `sudo -v`, one
`udevadm test --json=short -D` per live hidraw node and DFU device,
`install -m 0644` to `.tmp`, `mv -T`, `udevadm control --reload`,
`udevadm trigger --action=add --settle`. Three more appear only when their
condition is met: `rm -f` on a stale `.tmp`, `rm -f` on the `.tmp` of a failed
write, and `install -m 0600 -o <uid> -g <gid>` for an unreadable backup.
Nothing else runs through `sudo`.

## Sources

- systemd `rules.d/73-seat-late.rules.in`: `TAG=="uaccess|xaccess-*", ENV{MAJOR}!="", RUN{builtin}+="uaccess"`
  ([github](https://github.com/systemd/systemd/blob/main/rules.d/73-seat-late.rules.in)).
- systemd `rules.d/70-uaccess.rules.in`: upstream precedent for `uaccess` on `hidraw`
  ([github](https://github.com/systemd/systemd/blob/main/rules.d/70-uaccess.rules.in)).
- systemd `src/udev/udev-dump.c`: JSON keys `tags`, `currentTags`, `queuedCommands`
  ([github](https://github.com/systemd/systemd/blob/main/src/udev/udev-dump.c)).
- systemd `src/udev/udev-rules.c`, `udev_rules_load()`: a `-D` directory is prepended to the
  rules-directory list and every file is then sorted by basename, so a `70-` candidate in the
  temp dir both precedes `73-seat-late.rules` and masks an installed file of the same name
  ([github](https://github.com/systemd/systemd/blob/main/src/udev/udev-rules.c)).
- udevadm(8), systemd 261.2: `test` accepts `/dev/` paths, `--json=`, `-D` (added in 258),
  `control --reload`, `trigger --action= --settle` ([man.archlinux.org](https://man.archlinux.org/man/udevadm.8)).
- udev(7): `ATTRS{}` searches the devpath upwards ([man.archlinux.org](https://man.archlinux.org/man/udev.7)).
- Arch Wiki, Udev, "Allowing regular users to use devices": file must lexically precede
  `73-seat-late.rules` ([wiki.archlinux.org](https://wiki.archlinux.org/title/Udev)).
- systemd hwdb `20-usb-vendor-model.hwdb`: `usb:v0483pDF11*` is "STM Device in DFU Mode"
  ([github](https://github.com/systemd/systemd/blob/main/hwdb.d/20-usb-vendor-model.hwdb)).
- Arch `extra/dfu-util 0.11-3` ships `/usr/lib/udev/rules.d/60-dfuse.rules`
  ([archlinux.org](https://archlinux.org/packages/extra/x86_64/dfu-util/)).
- Linux `drivers/hid/hid-core.c` and `drivers/hid/hidraw.c`: `HID_ID`/`HID_NAME` uevent keys
  and the hidraw class device's HID parent ([github](https://github.com/torvalds/linux/tree/master/drivers/hid)).
- Keychron, "How to Restore Factory Settings and Update Firmware on Launcher": the DFU chooser
  ([keychron.com](https://www.keychron.com/pages/how-to-factory-reset-or-use-the-launcher-web-app-to-flash-firmware-for-your-keyboard)).
- Keychron, "How to Flash the Firmware for the Keychron Receiver": Launcher over 2.4 GHz from d.3.0/c.3.0
  ([keychron.com](https://www.keychron.com/pages/how-to-flash-the-firmware-for-the-keychron-receiver)).
- fish CHANGELOG: `string match --groups-only` (3.4.0), `string split --fields` and
  `string pad` (3.2.0) ([github](https://github.com/fish-shell/fish-shell/blob/master/CHANGELOG.rst)).
- fish `share/functions/diff.fish`: fish autoloads a `diff` function adding `--color=auto`
  ([github](https://github.com/fish-shell/fish-shell/blob/master/share/functions/diff.fish)).
