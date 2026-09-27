1.6.0 (2026-09-27)
------------------

  - install: a TMPDIR holding a backslash made sha256sum escape the staged
    name and every run rewrite a current rule; _sha strips that prefix
  - dry-run: name a node that vanished during the test, and stop blaming the
    candidate rule in the abort message
  - main: print an unexpected argument escaped, so an empty one shows as ''
  - docs: a Bluetooth board is unmatched because no Keychron or Lemokey USB
    device sits above its hidraw node


1.5.0 (2026-09-27)
------------------

  - settings: declare _TMP and _LOCK empty; an inherited or universal value
    reached the exit cleanup, whose rm -rf deleted that directory
  - main: read the flags with set -ql, as an inherited _flag_uninstall picked
    a mode; a signal during the last step exits 128+N, not the step's status
  - internals: run every external but sudo through `command`; a config.fish
    alias such as mkdir -p let a second run past a held lock
  - check: a rule that is not a root-owned 0644 regular file is drift (rc 4);
    the expected text at 0666, owned by the user or behind a symlink passed
  - install: rewrite such a rule, replacing a symlink, never reading a FIFO;
    the next hint names https://launcher.lemokey.com/ for Lemokey boards
  - uninstall: also remove a stale .rules.tmp left by a killed run
  - output: list a USB device with no product string as "unnamed" and its
    manufacturer only when set, not "()"


1.4.0 (2026-09-02)
------------------

  - rule: add usb 2e3c:df11, the AT32 ROM DFU of the Keychron 8K boards; the
    file text changes, so --check reports drift until --install is re-run
  - check: print the bootloader-mode hint whenever a dfu entry is listed
  - lock: report a lock directory that cannot be created as such, not as a
    held lock; ignore a relative XDG_RUNTIME_DIR and fall back to /tmp
  - install: abort when a stale .rules.tmp cannot be removed
  - settings: 0x362D is Lemokey-only, the one keyboards/keychron/x* entry
    being the Lemokey X0; the DFU_IDS comment names the AT32 DFU


1.3.0 (2026-08-30)
------------------

  - install: check the write that stages the candidate rule; an unwritable
    temp dir left -D empty and the dry-run passed against the installed file
  - lock: name the lock directory per uid; the /tmp fallback is shared, and a
    directory another user created there cannot be removed
  - settings: resolve XDG_STATE_HOME without declaring a local of that name,
    and treat a relative value as invalid, as the basedir spec requires
  - readers: report a hidraw node without HID_NAME as "unnamed", not "()"
  - usage: give -V --version its own line; print "verify failed" for exit 5
  - main: argparse -n is keychron-udev.fish, so an option error and the usage
    text name the same program


1.2.0 (2026-08-29)
------------------

  - logging: drop the run log; every line already goes to stderr, and the file
    grew in the state directory without rotation or a size bound
  - backup: timestamp the copy with milliseconds, so two runs in one second
    no longer overwrite each other; both paths write 0644
  - lock: fall back to /tmp when XDG_RUNTIME_DIR is set but is not a
    directory; mkdir failed there and reported a phantom lock holder
  - install: a failed udevadm trigger is a warning, not rc 1: the rule is
    already loaded, and verify reports whether access is live
  - rule: the generated comments no longer repeat the vendor ids; the file
    text changes, so --check reports drift on a 1.1.0 install until re-run
  - check: hash and diff the expected rule through a pipe; only --install
    stages a temp directory, for its udevadm test -D dry-run
  - diff: label the sides with the installed path and "expected", not the
    candidate's temp path
  - readers: one pass over the USB tree classifies boards and bootloaders
    together; the path builtin replaces a dirname process per device
  - preflight: drop the `id` existence check; the rules-directory check runs
    for the two modes that touch it, not for --verify
  - usage: list each short flag with its long form
  - internals: one signal handler for INT, TERM and HUP; mode-name dispatch
    in place of the switch block; --preserve-root dropped, being rm's default


1.1.0 (2026-08-29)
------------------

  - rule: add hidraw vid 362d and usb 342d:dfa0; Lemokey boards declare
    0x362D and the Lemokey P1 Pro is wb32-dfu, so neither line matched them
  - settings: the KC_VID and DFU_VID/DFU_PID scalars become the KC_VIDS and
    DFU_IDS lists; rule text, device scans and verify all iterate them
  - check: list and verify every matched vendor, not vid 3434 alone
  - uninstall: new -u/--uninstall mode; backs the rule up under the state
    dir, removes it with sudo, reloads udev; rc 0 when already absent
  - preflight: --uninstall needs sudo but not systemd-udev >= 258; the 258
    floor gates udevadm test -D, which only --install runs
  - verify: drop the getfacl ACL display and the acl dependency
  - main: stage a temp dir only for --check and --install


1.0.0 (2026-08-26)
------------------

  - preflight: refuse root (rc 2); require id, udevadm, USB sysfs and
    /etc/udev/rules.d; --install also needs sudo and systemd-udev >= 258
  - check: list Keychron USB devices, STM32 DFU boards and USB-bus hidraw
    nodes; compare 70-keychron.rules by sha256, rc 4 on drift or missing file
  - install: udevadm test --json=short -D dry-run on every live hidraw node
    and DFU device; require the uaccess tag and queued builtin, else abort
  - install: clear a stale .rules.tmp; leave an identical file untouched or
    back up a differing one (0644) with a diff; write via .tmp + mv -T; reload
  - install: back up a rule the invoking user cannot read with sudo install
    -m 0600 -o <uid> -g <gid>; abort before writing if it cannot be copied
  - install: udevadm trigger --action=add --settle on the live nodes so the
    ACL lands without a replug; a failed write removes its .tmp
  - verify: read-write check as the invoking user on every Keychron hidraw
    node and STM32 DFU node, rc 5 on failure; getfacl display informational
  - verify: DFU node paths built with string pad, not printf %03d, which reads
    a leading-zero busnum or devnum as octal
  - rule: hidraw VID 3434 plus usb 0483:df11, both TAG+="uaccess", file
    number 70 so 73-seat-late.rules applies it; no MODE=, the ACL is the grant
  - readers: sysfs and uevent reads are guarded; a node that disappears or is
    unreadable mid-scan is skipped, not reported on stderr
  - signals: INT/TERM/HUP exit 130/143/129 after cleanup; mkdir lock under
    XDG_RUNTIME_DIR; temp dir removed on exit
  - logging: the run log opens after preflight; every line is mirrored to it
    (0600); path shown at exit
  - output: diagnostics on stderr, stdout only for --help and --version; color
    only on a tty, disabled by non-empty NO_COLOR or TERM=dumb
  - output: sha256 and diff run through `command`, past fish's own diff
    function and any user function of either name
