# keychron-udev

Version 1.2.0 (2026-08-29). Script: `keychron-udev.fish`.

udev access for Keychron Launcher on Linux.

## Overview

Keychron Launcher talks to the board over WebHID and to its DFU bootloader over
WebUSB. Both need the browser to open a node Linux creates `root:root`:
`/dev/hidrawN` (0600) and `/dev/bus/usb/BBB/DDD` (0664). Without a rule the
Launcher stops at "HID device connected" and a flash stalls at 0 %.

`keychron-udev.fish` installs `/etc/udev/rules.d/70-keychron.rules`, tagging both
device classes `uaccess` so systemd-logind grants the active seat user a dynamic
ACL. No `input` or `plugdev` group, no `MODE="0666"`, no per-user `GROUP=`. Both
vendor IDs are covered: `3434` for Keychron boards, `362d` for Lemokey.

## Requirements

| Component  | Requirement                            | Notes |
|------------|----------------------------------------|-------|
| OS         | Arch-based distro, systemd-udev >= 258 | `udevadm test -D` added in 258; developed against 261.2 |
| Shell      | fish >= 3.6                            | newest features used: `path` (3.5), `string match -g` (3.4), `string split -f` and `string pad` (3.2) |
| Privileges | sudo for `--install` and `--uninstall` | `--check` and `--verify` never elevate |
| Tools      | coreutils                              | `id`, `install`, `mv -T`, `rm`, `rmdir`, `mkdir`, `mktemp`, `sha256sum`, `cat`, `date` |
| Optional   | diffutils                              | diff display before overwriting a rule |
| Browser    | native Chrome, Chromium or Edge        | Snap and Flatpak sandboxes need device access granted separately |
| Keyboard   | any Launcher board or receiver         | Keychron VID `3434`, Lemokey VID `362d` |

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

| Flag | Action | Elevates |
|------|--------|----------|
| `-c`, `--check`     | default; list matched devices and USB-bus hidraw nodes, compare the installed rule | no |
| `-i`, `--install`   | dry-run, back up and diff an existing file, write, reload, re-add live nodes, verify | sudo |
| `-v`, `--verify`    | confirm read-write access on every matched hidraw node and DFU device | no |
| `-u`, `--uninstall` | back up and remove the rule, then reload udev | sudo |
| `-h`, `--help`      | usage | no |
| `-V`, `--version`   | version | no |

Diagnostics go to stderr; stdout carries only `--help` and `--version`. Only
`--install` and `--uninstall` write anything, and only the paths below.
Color needs a terminal and is disabled by a non-empty `NO_COLOR` or `TERM=dumb`.

## Files

| Path | Purpose | Mode |
|------|---------|------|
| `/etc/udev/rules.d/70-keychron.rules` | the installed rule | 0644 root |
| `/etc/udev/rules.d/70-keychron.rules.tmp` | write staging; inert to udev, which reads only `*.rules`; removed on failure, cleared on the next `--install` | 0644 root |
| `$XDG_STATE_HOME/keychron-udev/<timestamp>-70-keychron.rules.bak` | backup of a replaced or removed rule; the timestamp carries milliseconds, so two runs in the same second keep both | 0644 |
| `$XDG_RUNTIME_DIR/keychron-udev.lock` | lock held during `--install` and `--uninstall` | dir |
| `$TMPDIR/keychron-udev.XXXXXX/` | `--install` only: stages the candidate for the `-D` dry-run, removed on exit | 0700 dir |

`XDG_STATE_HOME` defaults to `~/.local/state`. `XDG_RUNTIME_DIR` falls back to
`/tmp` when it is unset, empty, or not a directory. The state directory is
created 0700.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | ok |
| 1 | error: dry-run, backup, write, remove, reload or lock failure |
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
```

> [!WARNING]
> The file number is load-bearing. `73-seat-late.rules` runs the `uaccess`
> builtin, and it only sees tags added by files that sort before it. A
> `99-keychron.rules` with `TAG+="uaccess"` alone does nothing; the popular
> 99-numbered guides work only because they also set `GROUP=` or add the user to
> `input`.

The hidraw lines cover every HID interface on the USB bus belonging to either
vendor, a 2.4 GHz receiver included when it enumerates under one of them. They
set no `MODE=`: the node stays `0600 root:root` and the ACL is the only grant.
The
usb lines cover the two bootloaders a Launcher board re-enumerates as. Neither
line carries an `ACTION==` qualifier, so a synthetic re-add or change event
applies it too. Bluetooth-attached boards expose no `idVendor` attribute and are
never matched.

All 71 Keychron board configurations in Keychron's own QMK tree declare
`stm32-dfu` on vid `0x3434`, the K2 HE among them. The three Lemokey
configurations declare vid `0x362D`, and the Lemokey P1 Pro declares `wb32-dfu`
on a WB32F3G71. ZMK-based Ultra boards are not in that tree, so their bootloader
path is not covered here.

## What `--install` Does

1. Refuses root; checks `udevadm`, `sudo`, USB sysfs, the rules directory and
   `73-seat-late.rules`; requires systemd-udev 258 or later.
2. Takes a lock directory under `XDG_RUNTIME_DIR` or `/tmp`, authenticates with
   `sudo -v`.
3. Writes the candidate to a private temp directory and runs
   `sudo udevadm test --json=short -D <tmp> <node>` per live hidraw node and DFU
   device. `-D` directories are searched before `/etc`, so an already-installed
   file of the same name cannot shadow the candidate under test. The JSON must
   list `uaccess` under `tags` and a queued `uaccess` builtin under
   `queuedCommands` — the second is the proof the file sorts before
   `73-seat-late.rules`. Any failure aborts before a write.
4. Removes a stale `70-keychron.rules.tmp`; leaves an identical rule untouched.
5. Copies a differing rule to the state directory and diffs it against the new
   text. A rule the invoking user cannot read is copied with
   `sudo install -m 0644 -o <uid> -g <gid>`; a rule that cannot be copied at all
   aborts before a write.
6. Installs to `70-keychron.rules.tmp` (0644) and renames with `mv -T`, so udev
   never reads a partial file; a failed write removes the temporary file.
7. Runs `sudo udevadm control --reload`, then
   `sudo udevadm trigger --action=add --settle` on the live nodes, so a board
   already sitting in the bootloader gets its ACL without a replug. A node that
   disappeared mid-run makes this a warning, not a failure: the rule is written
   and loaded by then, and a replug applies it.
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

Every exit code, both privileged modes and the signal, lock and color paths are
exercised as an unprivileged user against a stub sysfs, reached by repointing
`SYSFS`, `DEVFS`, `RULES_DIR` and `SEAT_LATE`. A candidate numbered 99 instead
of 70 produces the tag without the queued builtin, which is the failure the file
number prevents.

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

**Flash stalls at 0 %.** The WebUSB chooser needs the DFU node. Run `--check`
while the board sits in bootloader mode; a `dfu` line names the pair it
enumerated as. If no `dfu` line appears, the board uses a bootloader this rule
does not cover — open an issue with the `lsusb` output.

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

## Security Notes

The hidraw lines grant the seat user read-write access to every HID interface of
both vendors, not only the raw-HID interface the Launcher uses; each DFU pair
also matches a bare development board carrying the same MCU. On a single-user
desktop that is the accepted trade-off. The rule never touches other vendors,
never uses world-writable modes, and logind removes the ACL when the session
stops being active.

`_sha` and `_diff` call `command sha256sum` and `command diff`, so no user
function can sit between the operator and the decision to overwrite a system rule
file. `SYSFS`, `DEVFS`, `RULES_DIR`, `RULE_PATH` and `SEAT_LATE` are fixed
`set -g` lines with no environment override, so nothing in the environment can
redirect a privileged write.

## Sources

- systemd `rules.d/73-seat-late.rules.in`: `TAG=="uaccess|xaccess-*", ENV{MAJOR}!="", RUN{builtin}+="uaccess"`
  ([github](https://github.com/systemd/systemd/blob/main/rules.d/73-seat-late.rules.in)).
- systemd `rules.d/50-udev-default.rules.in`: `SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", MODE="0664"`
  ([github](https://github.com/systemd/systemd/blob/main/rules.d/50-udev-default.rules.in)).
- systemd `src/udev/udev-dump.c`: JSON keys `tags`, `currentTags`, `queuedCommands`
  ([github](https://github.com/systemd/systemd/blob/main/src/udev/udev-dump.c)).
- systemd `src/udev/udev-rules.c`, `udev_rules_load()`: `-D` directories are placed
  ahead of the system rules directories, so the candidate outranks an installed
  file of the same name
  ([github](https://github.com/systemd/systemd/blob/main/src/udev/udev-rules.c)).
- systemd `src/udev/udevadm.c`, `print_version()`: `udevadm --version` prints the
  version as a bare integer
  ([github](https://github.com/systemd/systemd/blob/main/src/udev/udevadm.c)).
- udevadm(8), systemd 261.2: `test` accepts `/dev/` paths, `--json=`, `-D` (added in 258),
  `control --reload`, `trigger --action= --settle` ([man.archlinux.org](https://man.archlinux.org/man/udevadm.8)).
- udev(7): `ATTRS{}` searches the devpath upwards ([man.archlinux.org](https://man.archlinux.org/man/udev.7)).
- systemd hwdb `20-usb-vendor-model.hwdb`: `usb:v0483pDF11*` is "STM Device in DFU Mode"
  ([github](https://github.com/systemd/systemd/blob/main/hwdb.d/20-usb-vendor-model.hwdb)).
- Keychron `qmk_firmware`, `keyboards/keychron/k2_he/info.json`: `STM32F401`, `stm32-dfu`, vid `0x3434`
  ([github](https://github.com/Keychron/qmk_firmware/blob/hall_effect_playground/keyboards/keychron/k2_he/info.json)).
- Keychron `qmk_firmware`, `keyboards/lemokey/p1_pro/info.json`: `WB32F3G71`, `wb32-dfu`, vid `0x362D`
  ([github](https://github.com/Keychron/qmk_firmware/blob/wireless_playground/keyboards/lemokey/p1_pro/info.json)).
- QMK `qmk_udev`, `50-qmk.rules`: WB32 DFU is `342d:dfa0`
  ([github](https://github.com/qmk/qmk_udev/blob/main/50-qmk.rules)).
- Linux `drivers/hid/hidraw.c`: `HID_ID`/`HID_NAME` uevent keys on the hidraw parent
  ([github](https://github.com/torvalds/linux/tree/master/drivers/hid)).
