1.0.0 (2026-08-26)
------------------

  - preflight: refuse root (rc 2); require udevadm, USB sysfs and
    /etc/udev/rules.d; --install also requires sudo and systemd-udev >= 258
  - check: list Keychron USB devices and USB-bus hidraw nodes; compare
    70-keychron.rules with the expected text by sha256; rc 4 on drift
  - install: udevadm test --json=short -D dry-run on every live node; require
    the uaccess tag and a queued uaccess builtin, else abort before writing
  - install: leave an identical file untouched; back up a differing file to
    $XDG_STATE_HOME/keychron-udev with a diff; write via .tmp + mv -T; reload
  - install: udevadm trigger --action=add --settle on the live hidraw nodes so
    the ACL lands without a replug; then run the verify checks
  - install: a failed write removes its .tmp; empty XDG vars fall back per
    spec; '|' in sysfs strings is sanitized before field parsing
  - verify: read-write check as the invoking user on every Keychron hidraw
    node and on an STM32 DFU device node when present; rc 5 on failure
  - rule: hidraw VID 3434 (boards and Link receiver) plus usb 0483:df11 (STM32
    DFU), both TAG+="uaccess", file number 70 so 73-seat-late.rules applies it
  - signals: INT/TERM/HUP exit 130/143/129 after cleanup; mkdir lock under
    XDG_RUNTIME_DIR; temp dir removed on exit
  - output: diagnostics on stderr, stdout only for --help and --version; color
    only on a tty, disabled by non-empty NO_COLOR or TERM=dumb
