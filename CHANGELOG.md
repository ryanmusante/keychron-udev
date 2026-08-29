1.1.0 (2026-08-29)
------------------

  - rule: add hidraw vid 362d; Lemokey boards declare 0x362D, not 0x3434,
    in Keychron's own QMK tree, so the 3434 line never matched them
  - rule: add usb 342d:dfa0 (WB32 DFU); Lemokey P1 Pro is wb32-dfu, so a
    board in that bootloader got no ACL and its flash failed part-way
  - settings: the KC_VID and DFU_VID/DFU_PID scalars become the KC_VIDS and
    DFU_IDS lists; rule text, device scans and verify all iterate them
  - check: list and verify every matched vendor, not vid 3434 alone; a board
    in a non-ST bootloader is no longer reported as absent
  - uninstall: new -u/--uninstall mode; backs the rule up under the state
    dir, removes it with sudo, reloads udev; rc 0 when already absent
  - preflight: --uninstall needs sudo but not systemd-udev >= 258; the 258
    floor gates udevadm test -D, which only --install runs
  - install: the lock and the state-dir backup move into _lock and
    _save_aside, shared with --uninstall
  - docs: drop the receiver product id and the receiver firmware version
    floor; neither was verifiable from a first-party source
  - docs: cite 60-dfuse.rules as a path the dfu-util package installs, not
    as a rule whose contents this tool depends on
  - docs: record that all 71 Keychron board configs in Keychron's QMK tree
    declare stm32-dfu on vid 0x3434, the K2 HE among them


1.0.0 (2026-08-26)
------------------

  - preflight: refuse root (rc 2); require id, udevadm, USB sysfs and
    /etc/udev/rules.d; --install also needs sudo and systemd-udev >= 258
  - check: list Keychron USB devices, a board in the STM32 DFU bootloader, and
    USB-bus hidraw nodes
  - check: compare 70-keychron.rules with the expected text by sha256; rc 4 on
    drift, on a missing file, and on one that cannot be hashed
  - install: udevadm test --json=short -D dry-run on every live hidraw node
    and STM32 DFU device; require the uaccess tag and a queued uaccess
    builtin, else abort before writing
  - install: clear a stale .rules.tmp; leave an identical file untouched or
    back up a differing one (0644) with a diff; write via .tmp + mv -T; reload
  - install: back up a rule the invoking user cannot read with sudo install
    -m 0600 -o <uid> -g <gid>; abort before writing if it cannot be copied
  - install: udevadm trigger --action=add --settle on the live hidraw nodes
    and DFU devices so the ACL lands without a replug; then the verify checks
  - install: a failed write removes its .tmp; empty XDG vars fall back per
    spec; '|' in sysfs strings is sanitized before field parsing
  - verify: read-write check as the invoking user on every Keychron hidraw
    node and on an STM32 DFU device node when present; rc 5 on failure
  - verify: DFU node paths built with string pad, not printf %03d, which reads
    a leading-zero busnum or devnum as octal
  - verify: the getfacl ACL display is informational; a node without a named
    user entry cannot turn a passing verify into exit 1
  - rule: hidraw VID 3434 (boards and Link receiver) plus usb 0483:df11 (STM32
    DFU), both TAG+="uaccess", file number 70 so 73-seat-late.rules applies it
  - rule: no MODE= on the hidraw line; the node stays 0600 root:root and the
    uaccess ACL is the only grant
  - readers: sysfs and uevent reads are guarded; a node that disappears or is
    unreadable mid-scan is skipped, not reported on stderr
  - signals: INT/TERM/HUP exit 130/143/129 after cleanup; mkdir lock under
    XDG_RUNTIME_DIR; temp dir removed on exit
  - logging: the run log opens after preflight; every line of a check, install
    or verify run is mirrored to it (0600); path shown at exit
  - output: diagnostics on stderr, stdout only for --help and --version; color
    only on a tty, disabled by non-empty NO_COLOR or TERM=dumb
  - output: sha256 and diff run through `command`, past fish's own diff
    function and any user function of either name
