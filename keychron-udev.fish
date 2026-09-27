#!/usr/bin/env fish
# keychron-udev.fish 1.6.0 (2026-09-27): udev access for Keychron Launcher (WebHID) and DFU (WebUSB)
# Externals but sudo use `command`: fish wraps diff; config.fish, read by scripts too, may alias any

# ── SETTINGS ──
set -g VERSION 1.6.0
set -g RULE 70-keychron.rules
# 0x3434 is Keychron, 0x362D is Lemokey; see README
set -g KC_VIDS 3434 362d
# ST, WB32 and AT32 ROM DFU; atmel-dfu deliberately absent (README)
set -g DFU_IDS 0483:df11 342d:dfa0 2e3c:df11
set -g SYSFS /sys
set -g DEVFS /dev
set -g RULES_DIR /etc/udev/rules.d
set -g RULE_PATH $RULES_DIR/$RULE
set -g RULE_META '-rw-r--r-- uid 0'
set -g SEAT_LATE /usr/lib/udev/rules.d/73-seat-late.rules
# basedir spec: unset, empty or relative is invalid and falls back
set -l state "$XDG_STATE_HOME"
string match -q -- '/*' "$state"; or set state $HOME/.local/state
set -g STATE_DIR $state/keychron-udev
set -g _SIG 0
# empty globals: an inherited or universal _TMP would reach the exit rm -rf
set -g _TMP
set -g _LOCK

# ── OUTPUT AND LIFECYCLE ──
function _msg -d 'Print a leveled line to stderr' --argument-names lvl
    # a signal handler cannot exit; it records N and this exits 128+N
    test $_SIG -eq 0; or exit (math 128 + $_SIG)
    set -l c ''
    set -l r ''
    if test -t 2; and test -z "$NO_COLOR"; and test "$TERM" != dumb
        set -l map OK green WARN yellow FAIL red INFO blue
        set -l i (contains -i -- $lvl $map)
        test -n "$i"; and set c (set_color $map[(math $i + 1)])
        set r (set_color normal)
    end
    printf '%s%-4s%s %s\n' "$c" $lvl "$r" "$argv[2..-1]" >&2
    return 0
end

function _die -d 'Print a FAIL line and exit with the given code' --argument-names code
    _msg FAIL $argv[2..-1]
    exit $code
end

function _cleanup -d 'Remove the temp dir and lock on exit' --on-event fish_exit
    test -n "$_TMP"; and command rm -rf -- $_TMP
    test -n "$_LOCK"; and command rmdir -- $_LOCK 2>/dev/null
end

function _sig -d 'Record a signal for the next message or the final exit' --on-signal INT --on-signal TERM --on-signal HUP
    set -g _SIG 1
    test "$argv[1]" = SIGINT; and set -g _SIG 2
    test "$argv[1]" = SIGTERM; and set -g _SIG 15
end

function _usage -d 'Print the usage text to stdout'
    printf '%s\n' \
        "keychron-udev.fish $VERSION: udev access for Keychron Launcher (WebHID) and DFU (WebUSB)" \
        'Usage: keychron-udev.fish [-c|-i|-v|-u|-h|-V]' \
        "  -c --check      (default) list matched devices, compare $RULE; no sudo" \
        '  -i --install    dry-run, back up and diff, write, reload udev, re-add, verify' \
        '  -v --verify     confirm rw on every matched hidraw node and DFU device' \
        "  -u --uninstall  back up and remove $RULE, then reload udev" \
        '  -h --help       this text' \
        '  -V --version    print the version' \
        'Exit: 0 ok / 1 error / 2 usage or root / 3 preflight / 4 drift / 5 verify failed / 128+N signals'
end

# ── DEVICE READERS ──
function _attr -d 'Print a sysfs attribute, or nothing when it is unreadable' --argument-names f
    # callers quote it: an unquoted empty read shifts printf arguments
    test -r $f; and string trim -- (command cat -- $f 2>/dev/null)
end

# sysfs prints both ids lowercase, so no case folding
function _usb_scan -d 'List matched USB devices as kind|vid:pid|product|mfr|bus|dev'
    for f in $SYSFS/bus/usb/devices/*/idVendor
        set -l d (path dirname $f)
        set -l v (_attr $f)
        set -l p (_attr $d/idProduct)
        set -l kind usb
        if contains -- "$v:$p" $DFU_IDS
            set kind dfu
        else if not contains -- "$v" $KC_VIDS
            continue
        end
        set -l prod (_attr $d/product | string replace -a -- '|' '/')
        set -l mfr (_attr $d/manufacturer | string replace -a -- '|' '/')
        set -l bus (_attr $d/busnum)
        set -l num (_attr $d/devnum)
        printf '%s|%s:%s|%s|%s|%s|%s\n' $kind "$v" "$p" "$prod" "$mfr" "$bus" "$num"
    end
end

function _dfu_nodes -d 'Print the /dev/bus/usb node of every DFU device'
    for u in (_usb_scan)
        set -l f (string split -- '|' $u)
        test "$f[1]" = dfu; and test -n "$f[5]"; and test -n "$f[6]"; or continue
        # not %03d: fish printf silently reads a leading-zero field as octal
        printf '%s/bus/usb/%s/%s\n' $DEVFS (string pad -c 0 -w 3 -- $f[5]) (string pad -c 0 -w 3 -- $f[6])
    end
end

# Bluetooth HID (bus 0005) has no Keychron or Lemokey USB device above it: never rule-matched
function _hidraw_list -d 'List USB-bus hidraw nodes of a matched vendor as /dev/hidrawN|pid|HID_NAME'
    for u in $SYSFS/class/hidraw/hidraw*/device/uevent
        test -r $u; or continue
        set -l node (string replace -r -- '^.*/(hidraw[0-9]+)/device/uevent$' '$1' $u)
        set -l lines (command cat -- $u 2>/dev/null)
        set -l id (string match -rg -- '^HID_ID=0003:0000([0-9A-Fa-f]{4}):0000([0-9A-Fa-f]{4})$' $lines)
        test (count $id) -eq 2; and contains -- (string lower -- $id[1]) $KC_VIDS; or continue
        set -l name (string match -rg -- '^HID_NAME=(.*)$' $lines | string replace -a -- '|' '/')
        test -n "$name"; or set name unnamed
        printf '%s|%s|%s\n' $DEVFS/$node (string lower -- $id[2]) "$name"
    end
end

# ── RULE AND FILE HELPERS ──
function _rule_text -d 'Print the expected udev rule file'
    # the comments carry no ids, so the lists stay the only source
    printf '%s\n' \
        "# $RULE: written by keychron-udev.fish. Keep the number below 73:" \
        '# 73-seat-late.rules is what turns the uaccess tag into an ACL.' \
        '# Launcher (WebHID): raw HID on Keychron and Lemokey USB devices'
    for v in $KC_VIDS
        printf 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="%s", TAG+="uaccess"\n' $v
    end
    printf '%s\n' '# Launcher firmware flash (WebUSB): the bootloaders a board re-enumerates as'
    for id in $DFU_IDS
        set -l p (string split -- ':' $id)
        printf 'SUBSYSTEM=="usb", ATTRS{idVendor}=="%s", ATTRS{idProduct}=="%s", TAG+="uaccess"\n' $p[1] $p[2]
    end
end

function _sha -d 'Print the sha256 of a file, or of stdin for -' --argument-names f
    # sha256sum starts the line with a backslash when the name holds one or a newline
    command sha256sum -- $f 2>/dev/null | string match -rg -- '^\\\\?([0-9a-f]{64}) '
end

function _meta -d 'Print the mode string and owner uid of the installed rule'
    # %A not %F, whose file-type word is localized; no -L, so a symlink shows as l
    command stat -c '%A uid %u' -- $RULE_PATH 2>/dev/null; or echo 'stat failed'
end

function _clear_tmp -d 'Remove the staging file a killed run left behind'
    test -e $RULE_PATH.tmp; or return 0
    sudo rm -f -- $RULE_PATH.tmp; or _die 1 "cannot remove a stale $RULE_PATH.tmp"
    _msg INFO "removed a stale $RULE_PATH.tmp"
end

function _diff -d 'Diff a file against the expected rule, to stderr' --argument-names old
    command -q diff; or return 0
    _rule_text | command diff -u --label $old --label expected -- $old - >&2
    return 0
end

function _lock -d 'Take the single-run lock for a privileged mode'
    set -l lockdir /tmp
    string match -q -- '/*' "$XDG_RUNTIME_DIR"; and test -d "$XDG_RUNTIME_DIR"; and set lockdir $XDG_RUNTIME_DIR
    # per-uid: /tmp is shared and a foreign lock dir cannot be removed
    set -l lock $lockdir/keychron-udev-(command id -u).lock
    if not command mkdir -- $lock 2>/dev/null
        test -d $lock; and _die 1 "another run holds $lock (rmdir it if no run is active)"
        _die 1 "cannot create $lock"
    end
    set -g _LOCK $lock
end

function _save_aside -d 'Copy the installed rule under the state dir, print the path'
    command mkdir -p -m 0700 -- $STATE_DIR; or _die 1 "cannot create $STATE_DIR"
    # milliseconds: two runs in one second would overwrite one backup
    set -l bak $STATE_DIR/(command date +%Y%m%dT%H%M%S.%3N)-$RULE.bak
    # install not cp: umask-immune; sudo fallback for an unreadable rule
    command install -m 0644 -- $RULE_PATH $bak 2>/dev/null
    or sudo install -m 0644 -o (command id -u) -g (command id -g) -- $RULE_PATH $bak
    or _die 1 "backup failed: $bak"
    echo $bak
end

function _write_rule -d 'Keep a current rule; back up and replace any other' --argument-names src
    _clear_tmp
    set -l meta (_meta)
    set -l want (_sha $src)
    set -l have
    # the right text in a 0666, user-owned or symlinked file is still rewritten
    test "$meta" = "$RULE_META"; and set have (_sha $RULE_PATH)
    if test -n "$have"; and test "$have" = "$want"
        _msg OK "$RULE_PATH already current"
        return 0
    end
    if test -f $RULE_PATH
        set -l bak (_save_aside)
        _msg INFO "existing $RULE ($meta) backed up to $bak; diff (installed -> expected):"
        _diff $bak
    end
    if not sudo install -m 0644 -- $src $RULE_PATH.tmp; or not sudo mv -T -- $RULE_PATH.tmp $RULE_PATH
        sudo rm -f -- $RULE_PATH.tmp
        _die 1 "write failed: $RULE_PATH"
    end
    _msg OK "wrote $RULE_PATH (0644)"
end

# ── PREFLIGHT AND DRY-RUN ──
function _preflight -d 'Refuse root and missing dependencies; gate udev >= 258' --argument-names mode
    test (command id -u) -ne 0; or _die 2 'run as your desktop user, not root'
    command -q udevadm; or _die 3 'udevadm not found'
    test -d $SYSFS/bus/usb/devices; or _die 3 "no USB sysfs under $SYSFS"
    test -e $SEAT_LATE; or _msg WARN "$SEAT_LATE missing: nothing would apply the uaccess ACL"
    contains -- $mode install uninstall; or return 0
    command -q sudo; or _die 3 'sudo not found'
    test -d $RULES_DIR; or _die 3 "missing $RULES_DIR"
    # only --install runs udevadm test -D, so only it needs udev 258
    test "$mode" = install; or return 0
    set -l ver (command udevadm --version | string match -r -- '^[0-9]+')
    test -n "$ver"; and test $ver -ge 258; or _die 3 "udevadm test -D needs systemd >= 258 (found: $ver)"
end

# -D outranks /etc for an equal filename: this tests the candidate
function _dry_run -d 'Prove the staged rule tags uaccess and queues the builtin' --argument-names node
    set -l json (sudo udevadm test --json=short -D $_TMP $node 2>/dev/null | string collect)
    set -l why
    test -n "$json"; or set why 'udevadm test produced no JSON'
    test -n "$json"; or test -e $node; or set why 'node vanished; replug and re-run'
    test -n "$why"; or string match -qr -- '"tags":\[[^]]*"uaccess"' $json; or set why 'no uaccess tag'
    test -n "$why"; or string match -qr -- '"command":"uaccess"' $json; or set why 'no uaccess builtin'
    if test -n "$why"
        _msg FAIL "$node: $why"
        return 1
    end
    _msg OK "$node: uaccess tag set and ACL builtin queued"
end

# ── MODES ──
function _inventory -d 'Print the keyboard, DFU and hidraw devices present'
    set -l usb (_usb_scan)
    for u in $usb
        set -l f (string split -- '|' $u)
        set -l name $f[3]
        test -n "$name"; or set name unnamed
        test -n "$f[4]"; and set name "$name ($f[4])"
        _msg INFO "$f[1] $f[2] $name bus $f[5] dev $f[6]"
    end
    if test (count $usb) -eq 0
        _msg WARN 'no Keychron or Lemokey USB device: set the toggle to Cable, or plug the receiver in'
    else if string match -q -- 'dfu|*' $usb
        _msg INFO 'board is in bootloader mode; it re-enumerates after a flash'
    end
    for h in (_hidraw_list)
        set -l f (string split -- '|' $h)
        _msg INFO "hidraw $f[1] pid $f[2] ($f[3])"
    end
end

function _check -d 'Compare the installed rule with the expected file; return 4 on drift'
    _inventory
    if not test -e $RULE_PATH
        _msg WARN "$RULE_PATH missing; --install writes:"
        _rule_text >&2
        return 4
    end
    set -l meta (_meta)
    if test "$meta" != "$RULE_META"
        _msg WARN "$RULE_PATH is not a root-owned 0644 regular file ($meta)"
        return 4
    end
    set -l have (_sha $RULE_PATH)
    # quoted: an empty unquoted substitution collapses test's operands
    if test -z "$have"
        _msg WARN "$RULE_PATH could not be read"
        return 4
    end
    set -l want (_rule_text | _sha -)
    if test "$have" != "$want"
        _msg WARN "$RULE_PATH differs from the expected rule (installed -> expected):"
        _diff $RULE_PATH
        return 4
    end
    _msg OK "$RULE_PATH matches the expected rule"
end

function _install -d 'Dry-run the candidate, write it, reload udev, re-add the live nodes, verify'
    _lock
    _inventory
    sudo -v; or _die 3 'sudo authentication failed'
    set -g _TMP (command mktemp -d --tmpdir keychron-udev.XXXXXX); or _die 1 'mktemp failed'
    # a failed stage would leave -D empty and the dry-run pass on /etc
    _rule_text >$_TMP/$RULE; or _die 1 "cannot stage the candidate rule in $_TMP"
    set -l nodes (_hidraw_list | string split -f1 -- '|') (_dfu_nodes)
    if test (count $nodes) -eq 0
        _msg WARN 'no hidraw or DFU node to dry-run against; installing the rule unverified'
    end
    for n in $nodes
        _dry_run $n; or _die 1 'udevadm dry-run failed; nothing written'
    end
    _write_rule $_TMP/$RULE
    sudo udevadm control --reload; or _die 1 'udevadm control --reload failed'
    if test (count $nodes) -gt 0
        # the rule is live already; a vanished node only costs a replug
        sudo udevadm trigger --action=add --settle $nodes
        and _msg OK "re-added $nodes"
        or _msg WARN 'udevadm trigger failed; replug the device to pick the rule up'
    end
    _verify
    _msg INFO 'next: https://launcher.keychron.com/ (Lemokey: https://launcher.lemokey.com/) in Chrome, Connect, Firmware Update'
end

function _uninstall -d 'Back up and remove the installed rule, then reload udev'
    _lock
    if test -e $RULE_PATH; or test -e $RULE_PATH.tmp
        sudo -v; or _die 3 'sudo authentication failed'
        _clear_tmp
    end
    if not test -e $RULE_PATH
        _msg OK "$RULE_PATH not present"
        return 0
    end
    if test -f $RULE_PATH
        set -l bak (_save_aside)
        _msg INFO "$RULE backed up to $bak"
    end
    sudo rm -f -- $RULE_PATH; or _die 1 "remove failed: $RULE_PATH"
    _msg OK "removed $RULE_PATH"
    sudo udevadm control --reload; or _die 1 'udevadm control --reload failed'
    _msg INFO 'live nodes keep their ACL until re-added: replug the device, or reboot'
end

function _rw -d 'Report read-write access on one node' --argument-names node label
    if test -r $node; and test -w $node
        _msg OK "$node rw for $USER ($label)"
        return 0
    end
    _msg FAIL "$node not accessible for $USER ($label)"
    return 1
end

function _verify -d 'Check read-write access on every matched node; exit 5 on failure'
    set -l hid (_hidraw_list)
    set -l dfu (_dfu_nodes)
    test (count $hid $dfu) -gt 0; or _msg WARN 'no matched hidraw node or DFU device present'
    set -l fail 0
    for h in $hid
        set -l f (string split -- '|' $h)
        _rw $f[1] $f[3]; or set fail 1
    end
    for n in $dfu
        _rw $n 'DFU bootloader'; or set fail 1
    end
    test $fail -eq 0; or _die 5 'access not live: replug the device, or run --install'
end

# ── MAIN ──
argparse -n keychron-udev.fish -x check,install,verify,uninstall \
    h/help V/version c/check i/install v/verify u/uninstall -- $argv; or exit 2
# -l: argparse sets locals, and an inherited or universal _flag_* is no option
if set -ql _flag_help
    _usage
    exit 0
end
if set -ql _flag_version
    echo "keychron-udev.fish $VERSION"
    exit 0
end
test (count $argv) -eq 0; or _die 2 "unexpected argument: "(string escape -- $argv[1])
set -l mode check
set -ql _flag_install; and set mode install
set -ql _flag_verify; and set mode verify
set -ql _flag_uninstall; and set mode uninstall
_preflight $mode
# mode is one of the four literals set above, never user text
_$mode
set -l rc $status
# a signal in the last step meets no later _msg, so it becomes 128+N here
test $_SIG -eq 0; or set rc (math 128 + $_SIG)
exit $rc
