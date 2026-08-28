1.0.0 (2026-08-26)
------------------

  - preflight: refuse root (rc 2); require id, udevadm, USB sysfs and
    /etc/udev/rules.d; --install also requires sudo and systemd-udev >= 258
  - check: list Keychron USB devices, a board sitting in the STM32 DFU
    bootloader, and USB-bus hidraw nodes
  - check: compare 70-keychron.rules with the expected text by sha256; rc 4 on
    drift, on a missing file, and on one that cannot be hashed
  - install: udevadm test --json=short -D dry-run on every live node; require
    the uaccess tag and a queued uaccess builtin, else abort before writing
  - install: clear a stale .rules.tmp, then leave an identical file untouched
    or back up a differing one with a diff; write via .tmp + mv -T; reload
  - install: back up a rule the invoking user cannot read with sudo install
    -m 0600 -o <uid> -g <gid>; abort before writing if it cannot be copied
  - install: udevadm trigger --action=add --settle on the live hidraw nodes so
    the ACL lands without a replug; then run the verify checks
  - install: a failed write removes its .tmp; empty XDG vars fall back per
    spec; '|' in sysfs strings is sanitized before field parsing
  - verify: read-write check as the invoking user on every Keychron hidraw
    node and on an STM32 DFU device node when present; rc 5 on failure
  - verify: DFU node paths are built with string pad, so a leading-zero busnum
    or devnum is not read as an octal number
  - rule: hidraw VID 3434 (boards and Link receiver) plus usb 0483:df11 (STM32
    DFU), both TAG+="uaccess", file number 70 so 73-seat-late.rules applies it
  - rule: no MODE= on the hidraw line; the node stays 0600 root:root and the
    uaccess ACL is the only grant
  - readers: sysfs and uevent reads are guarded, so a node that disappears or
    is unreadable mid-scan is skipped rather than reported on stderr
  - signals: INT/TERM/HUP exit 130/143/129 after cleanup; mkdir lock under
    XDG_RUNTIME_DIR; temp dir removed on exit
  - logging: the run log opens after preflight; every line of a check, install
    or verify run is mirrored to it (0600); path shown at exit
  - output: diagnostics on stderr, stdout only for --help and --version; color
    only on a tty, disabled by non-empty NO_COLOR or TERM=dumb
  - output: sha256 and diff run through `command`, so neither fish's own diff
    function nor a user function can alter a comparison or a displayed diff
