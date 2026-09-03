# keychron-udev

Version 1.4.0 (2026-09-02). Script: `keychron-udev.fish`.

udev access for Keychron Launcher on Linux.

## Overview

Keychron Launcher talks to the board over WebHID and to its DFU bootloader over
WebUSB. Both need the browser to open a node Linux creates `root:root`:
`/dev/hidrawN` (0600) and `/dev/bus/usb/BBB/DDD` (0664). Without a rule the
Launcher stops at "HID device connected" and a flash stalls at 0 %.

`keychron-udev.fish` installs `/etc/udev/rules.d/70-keychron.rules`, tagging both
device classes `uaccess` so systemd-logind grants the active seat user a dynamic
ACL. No `input` or `plugdev` group, no `MODE="0666"`, no per-user `GROUP=`. Vid
`3434` is Keychron and `362d` is Lemokey; both are covered.

## Requirements

| Component  | Requirement                               | Notes |
|------------|-------------------------------------------|-------|
| OS         | Arch-based distro; udev >= 258 to install | `udevadm test -D` needs 258; the floor is `--install` only |
| Shell      | fish >= 3.6                               | newest feature used: `path` (3.5) |
| Privileges | sudo for `--install` and `--uninstall`    | `--check` and `--verify` never elevate |
| Tools      | coreutils                                 | `id`, `install`, `mv -T`, `rm`, `rmdir`, `mkdir`, `mktemp`, `sha256sum`, `cat`, `date` |
| Optional   | diffutils                                 | diff display on drift and before overwriting a rule |
| Browser    | native Chrome, Chromium or Edge           | Snap and Flatpak sandboxes need device access granted separately |
| Keyboard   | any Launcher board or receiver            | vids `3434` and `362d` |

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
> Do not unplug the cable during a flash, and do not put a second board into
> bootloader mode at the same time: two bootloader entries in the WebUSB chooser
> differ only by serial number.

## Modes

| Flag                | Action | Elevates |
|---------------------|--------|----------|
| `-c`, `--check`     | default; list matched devices and USB-bus hidraw nodes, compare the installed rule | no       |
| `-i`, `--install`   | dry-run, back up and diff an existing file, write, reload, re-add live nodes, verify | sudo     |
| `-v`, `--verify`    | confirm read-write access on every matched hidraw node and DFU device | no       |
| `-u`, `--uninstall` | back up and remove the rule, then reload udev | sudo     |
| `-h`, `--help`      | usage | no       |
| `-V`, `--version`   | version | no       |

Diagnostics go to stderr; stdout carries only `--help` and `--version`. Only
`--install` and `--uninstall` write, and only the paths below. Color needs a
terminal and is disabled by a non-empty `NO_COLOR` or `TERM=dumb`.

## Files

| Path | Purpose | Mode |
|------|---------|------|
| `/etc/udev/rules.d/70-keychron.rules` | the installed rule | 0644 root |
| `/etc/udev/rules.d/70-keychron.rules.tmp` | write staging, inert to udev; removed on failure or by the next `--install` | 0644 root |
| `$XDG_STATE_HOME/keychron-udev/<timestamp>-70-keychron.rules.bak` | backup of a replaced or removed rule; millisecond timestamp | 0644 |
| `$XDG_RUNTIME_DIR/keychron-udev-<uid>.lock` | lock held during `--install` and `--uninstall` | dir |
| `$TMPDIR/keychron-udev.XXXXXX/` | `--install` only: stages the candidate for the dry-run, removed on exit | 0700 dir |

`XDG_STATE_HOME` must be absolute; unset, empty or relative falls back to
`~/.local/state`. `XDG_RUNTIME_DIR` falls back to `/tmp` when unset, empty,
relative or not a directory; `TMPDIR` defaults to `/tmp`. The state directory
is created 0700.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | ok |
| 1 | error: temp dir, staging, dry-run, backup, stale `.tmp`, write, remove, reload or lock failure |
| 2 | usage error, or run as root |
| 3 | preflight: missing `udevadm`, `sudo`, USB sysfs or rules dir; udev < 258 for `--install`; sudo authentication failed |
| 4 | drift (`--check`): rule missing, unreadable, not a regular file, or differing from the expected text |
| 5 | verify failed: a node is not readable and writable for the user |
| 129, 130, 143 | SIGHUP, SIGINT, SIGTERM after cleanup |

## The Rule

```
# 70-keychron.rules: written by keychron-udev.fish. Keep the number below 73:
# 73-seat-late.rules is what turns the uaccess tag into an ACL.
# Launcher (WebHID): raw HID on Keychron and Lemokey USB devices
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="362d", TAG+="uaccess"
# Launcher firmware flash (WebUSB): the bootloaders a board re-enumerates as
SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="342d", ATTRS{idProduct}=="dfa0", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="2e3c", ATTRS{idProduct}=="df11", TAG+="uaccess"
```

> [!WARNING]
> The file number is load-bearing. `73-seat-late.rules` runs the `uaccess`
> builtin, and it only sees tags added by files that sort before it. A
> `99-keychron.rules` with `TAG+="uaccess"` alone does nothing; the popular
> 99-numbered guides work only because they also set `GROUP=` or add the user to
> `input`.

The hidraw lines cover every HID interface of either vendor on the USB bus, a
2.4 GHz receiver included; they set no `MODE=`, so the ACL is the only grant.
The usb lines cover the three bootloaders a Launcher board re-enumerates as.
Bluetooth-attached boards expose no `idVendor` attribute and are never matched.

The ids come from Keychron's QMK fork, `github.com/Keychron/qmk_firmware`,
measured on 2026-09-02 across its `2025q3`, `wireless_playground`,
`hall_effect_playground` and `wls_2025q1` branches. `stm32-dfu` (`0483:df11`)
is the bulk, the K2 HE included; `wb32-dfu` (`342d:dfa0`) is the Lemokey P1 Pro
and a minority of Keychron boards; `at32-dfu` (`2e3c:df11`) is the AT32F405 8K
series. `keyboards/keychron/q1v1` is `atmel-dfu` (`03eb:2ff4`) and deliberately
absent: the Q1 V1 predates Launcher, and the pair would tag every ATmega32U4
sitting in DFU mode. No board uses an APM32 or GD32V bootloader; the ZMK-based
Ultra boards are not in this tree and are not covered.

## What `--install` Does

1. Refuses root; checks `udevadm`, `sudo`, USB sysfs and the rules directory;
   warns when `73-seat-late.rules` is missing; requires udev 258 or later.
2. Takes a per-uid lock, authenticates with `sudo -v`.
3. Stages the candidate in a private temp directory and runs
   `sudo udevadm test --json=short -D <tmp> <node>` on every live hidraw node
   and DFU device. The JSON must list `uaccess` under `tags` and a queued
   `uaccess` builtin under `queuedCommands`; any failure aborts before a
   write. With no live node the rule is written unverified, after a warning.
4. Removes a stale `70-keychron.rules.tmp`, aborting if it cannot; leaves an
   identical rule untouched.
5. Backs a differing rule up to the state directory and shows the diff; a
   rule that cannot be copied aborts before a write.
6. Installs to `70-keychron.rules.tmp` (0644) and renames with `mv -T`; a
   failed write removes the temporary file.
7. Runs `sudo udevadm control --reload`, then
   `sudo udevadm trigger --action=add --settle` on the live nodes; a failed
   trigger is a warning, and a replug applies the rule.
8. Runs the `--verify` checks.

## Verification

```fish
fish --no-execute keychron-udev.fish        # syntax gate
./keychron-udev.fish --check
./keychron-udev.fish --verify
sudo udevadm test --json=pretty /dev/hidrawN 2>/dev/null | jq '.tags, .queuedCommands'
```

`jq` is optional. In Chrome, `chrome://device-log` lists every HID and USB access
attempt with its error.

## Uninstall

`./keychron-udev.fish --uninstall` copies the rule to the state directory,
removes it, and reloads udev. Existing nodes keep their ACL until re-added:
replug the board or reboot. By hand:

```fish
sudo rm /etc/udev/rules.d/70-keychron.rules
sudo udevadm control --reload
```

## Troubleshooting

**Launcher says "HID device connected" and stops.** The browser could not open
`/dev/hidrawN`. Run `--verify`; a FAIL line names the node. Re-run `--install`,
or replug the board.

**Flash stalls at 0 %.** Run `--check` while the board sits in bootloader mode;
a `dfu` line names the pair it enumerated as. No `dfu` line means a bootloader
this rule does not cover: open an issue with the `lsusb` output.

**Chrome is a Flatpak.** `flatpak override --user --device=all com.google.Chrome`.
Snap Chromium is sandboxed as well.

**Board is in Bluetooth mode.** Switch the toggle to Cable, or to 2.4 GHz with
the receiver plugged in.

**Dry-run fails with "no uaccess builtin".** `73-seat-late.rules` does not see
the tag. Check `ls /usr/lib/udev/rules.d/73-seat-late.rules` and any override in
`/etc/udev/rules.d/`.

**Verification fails over SSH.** The ACL goes to the active local seat session.
Run the script from the desktop session that will run Chrome.

**Install stops with "another run holds <dir>".** A previous run was killed
before cleanup; remove the named directory with `rmdir`. A "cannot create"
message instead means the parent is not writable, or a file sits at that name.

## Security Notes

The hidraw lines grant the seat user read-write access to every HID interface of
both vendors, not only the raw-HID interface the Launcher uses; each DFU pair
also matches a bare development board carrying the same MCU. On a single-user
desktop that is the accepted trade-off. logind removes the ACL when the session
stops being active. The one privileged write outside `/etc/udev/rules.d` is the
backup: a rule the invoking user cannot read is copied with `sudo install` to
`$XDG_STATE_HOME/keychron-udev`, owned by that user at 0644.
