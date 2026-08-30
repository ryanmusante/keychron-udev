1.2.0 (2026-08-29)
------------------

  - logging: drop the run log; every line already goes to stderr, and the file
    grew in the state directory without rotation or a size bound
  - backup: timestamp the copy with milliseconds, so two runs inside the same
    second no longer overwrite one another's file; both paths write 0644
  - lock: fall back to /tmp when XDG_RUNTIME_DIR is set but is not a
    directory; mkdir failed there and reported a phantom lock holder
  - install: a failed udevadm trigger is a warning, not rc 1; the rule is
    written and loaded by then, and the verify checks that follow report
    whether access is live
  - rule: the generated comments no longer repeat the vendor ids the rule
    lines carry, so a vid added to KC_VIDS or DFU_IDS cannot leave the prose
    stale; the file text changes, so --check reports drift on a 1.1.0 install
    until --install is re-run
  - check: hash and diff the expected rule through a pipe; only --install
    stages a temp directory, for its udevadm test -D dry-run
  - diff: label the sides with the installed path and "expected" instead of
    the temp path the candidate happened to occupy
  - readers: one pass over the USB tree classifies boards and bootloaders
    together, replacing the per-vendor and per-bootloader passes; the path
    builtin replaces a dirname process per device
  - preflight: drop the `id` existence check, the only one of its kind among a
    dozen coreutils callers; the rules-directory check now runs for the two
    modes that touch it, not for --verify
  - usage: list each short flag with its long form
  - internals: one signal handler for INT, TERM and HUP in place of three;
    mode-name dispatch in place of the switch block; --preserve-root dropped
    from the temp-dir removal, where it is rm's default


1.1.0 (2026-08-29)
------------------

  - rule: add hidraw vid 362d and usb 342d:dfa0; Lemokey boards declare
    0x362D and the Lemokey P1 Pro is wb32-dfu, so neither line matched them
  - settings: the KC_VID and DFU_VID/DFU_PID scalars become the KC_VIDS and
    DFU_IDS lists; rule text, device scans and verify all iterate them
  - check: list and verify every matched vendor, not vid 3434 alone; a board
    in a non-ST bootloader is no longer reported as absent
  - uninstall: new -u/--uninstall mode; backs the rule up under the state
    dir, removes it with sudo, reloads udev; rc 0 when already absent
  - preflight: --uninstall needs sudo but not systemd-udev >= 258; the 258
    floor gates udevadm test -D, which only --install runs
  - verify: drop the getfacl ACL display and the acl dependency; the
    read-write test already decides the result
  - main: stage a temp dir only for --check and --install; --verify and
    --uninstall never write a candidate file
  - docs: drop the receiver product id, the receiver firmware floor and the
    claim about 60-dfuse.rules contents; none was verifiable first-hand


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
