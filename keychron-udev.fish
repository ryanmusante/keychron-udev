#!/usr/bin/env fish
# keychron-udev.fish 1.0.0 (2026-08-26): udev access for Keychron Launcher (WebHID) and DFU (WebUSB)
# Exit codes: 0 ok / 1 error / 2 usage or root / 3 preflight / 4 drift (--check) / 5 verify failed / 128+N signals

# ── SETTINGS ──
set -g VERSION 1.0.0
set -g RULE 70-keychron.rules
set -g KC_VID 3434
set -g DFU_VID 0483
set -g DFU_PID df11
set -g SYSFS /sys
set -g DEVFS /dev
set -g RULES_DIR /etc/udev/rules.d
set -g SEAT_LATE /usr/lib/udev/rules.d/73-seat-late.rules
test -n "$XDG_STATE_HOME"; or set -l XDG_STATE_HOME $HOME/.local/state
set -g STATE_DIR $XDG_STATE_HOME/keychron-udev
set -g _TMP ''
set -g _LOCK ''
set -g _LOG ''
set -g _SIG 0
set -g NODEV 'no Keychron USB device: put the toggle on Cable, or plug the receiver in'
set -g INDFU 'board is in bootloader mode; it re-enumerates after a flash'
set -g NONODE 'no Keychron hidraw or DFU node to dry-run against; installing the rule unverified'

# ── OUTPUT AND LIFECYCLE ──
# a handler cannot exit with a code, so it records the number and the next message exits 128+N
function _msg -d 'Print a leveled line to stderr and the run log' --argument-names lvl
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
    test -n "$_LOG"; and printf '%s %-4s %s\n' (date +%Y-%m-%dT%H:%M:%S%z) $lvl "$argv[2..-1]" >>$_LOG
    return 0
end

function _die -d 'Print a FAIL line and exit with the given code' --argument-names code
    _msg FAIL $argv[2..-1]
    exit $code
end

function _log_open -d 'Open the run log under the state dir' --argument-names mode
    mkdir -p -m 0700 -- $STATE_DIR; or return 0
    set -g _LOG $STATE_DIR/keychron-udev.log
    touch -- $_LOG; and chmod 0600 -- $_LOG; or set -g _LOG ''
    test -n "$_LOG"; and printf '=== keychron-udev.fish %s mode=%s user=%s\n' $VERSION $mode "$USER" >>$_LOG
    return 0
end

function _cleanup -d 'Remove the temp dir and lock on exit' --on-event fish_exit
    test -n "$_TMP"; and rm -rf --preserve-root -- $_TMP
    test -n "$_LOCK"; and rmdir -- $_LOCK 2>/dev/null
end
function _sig_int -d 'Record SIGINT for the next message' --on-signal INT
    set -g _SIG 2
end
function _sig_term -d 'Record SIGTERM for the next message' --on-signal TERM
    set -g _SIG 15
end
function _sig_hup -d 'Record SIGHUP for the next message' --on-signal HUP
    set -g _SIG 1
end

function _usage -d 'Print the usage text to stdout'
    printf '%s\n' \
        "keychron-udev.fish $VERSION: udev access for Keychron Launcher (WebHID) and DFU (WebUSB)" \
        'Usage: keychron-udev.fish [-c|--check | -i|--install | -v|--verify] [-h|--help] [-V|--version]' \
        "  --check    (default) list Keychron and DFU devices, compare $RULE with the" \
        '             expected rule; no system change, no sudo' \
        '  --install  dry-run with udevadm test -D, back up and diff any existing file,' \
        '             write atomically, reload udev, re-add the live nodes, verify' \
        '  --verify   confirm the current user has rw on every Keychron hidraw node' \
        '             and on an STM32 DFU device when present' \
        'Exit: 0 ok / 1 error / 2 usage or root / 3 preflight / 4 drift / 5 verify failed / 128+N signals' \
        'Env:  NO_COLOR (non-empty) or TERM=dumb disable color; XDG_STATE_HOME holds the log and backups'
end

# ── DEVICE READERS ──
# callers quote the result: an unquoted empty read would shift printf arguments
function _attr -d 'Print a sysfs attribute, or nothing when it is unreadable' --argument-names f
    test -r $f; and string trim -- (cat -- $f 2>/dev/null)
end

function _usb_list -d 'List one vendor as vid:pid|product|mfr|bus|dev' --argument-names vid pid
    for f in $SYSFS/bus/usb/devices/*/idVendor
        set -l d (dirname -- $f)
        set -l v (_attr $f)
        set -l p (_attr $d/idProduct)
        test "$v" = $vid; or continue
        test -n "$pid"; and test "$p" != $pid; and continue
        set -l prod (_attr $d/product | string replace -a -- '|' '/')
        set -l mfr (_attr $d/manufacturer | string replace -a -- '|' '/')
        set -l bus (_attr $d/busnum)
        set -l num (_attr $d/devnum)
        printf '%s:%s|%s|%s|%s|%s\n' $vid "$p" "$prod" "$mfr" "$bus" "$num"
    end
end

# Bluetooth HID (bus 0005) exposes no idVendor attribute and is never rule-matched
function _hidraw_list -d 'List USB-bus Keychron hidraw nodes as /dev/hidrawN|pid|HID_NAME'
    for u in $SYSFS/class/hidraw/hidraw*/device/uevent
        test -r $u; or continue
        set -l node (string replace -r -- '^.*/(hidraw[0-9]+)/device/uevent$' '$1' $u)
        set -l lines (cat -- $u 2>/dev/null)
        set -l id (string match -rg -- '^HID_ID=0003:0000([0-9A-Fa-f]{4}):0000([0-9A-Fa-f]{4})$' $lines)
        test (count $id) -eq 2; and test (string lower -- $id[1]) = $KC_VID; or continue
        set -l name (string match -rg -- '^HID_NAME=(.*)$' $lines | string replace -a -- '|' '/')
        printf '%s|%s|%s\n' $DEVFS/$node (string lower -- $id[2]) "$name"
    end
end

function _dfu_nodes -d 'Print the /dev/bus/usb node of every STM32 DFU device'
    for u in (_usb_list $DFU_VID $DFU_PID)
        set -l f (string split -- '|' $u)
        test -n "$f[4]"; and test -n "$f[5]"; or continue
        # not %03d: fish printf reads a leading-zero field as octal (012 -> 010, silently)
        printf '%s/bus/usb/%s/%s\n' $DEVFS (string pad -c 0 -w 3 -- $f[4]) (string pad -c 0 -w 3 -- $f[5])
    end
end

# ── RULE AND FILE HELPERS ──
function _rule_text -d 'Print the expected udev rule file'
    printf '%s\n' \
        "# $RULE: written by keychron-udev.fish. Keep the number below 73:" \
        '# 73-seat-late.rules is what turns the uaccess tag into an ACL.' \
        '# Keychron Launcher (WebHID): raw HID on Keychron USB devices, including the 2.4 GHz Link receiver' \
        "SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$KC_VID\", TAG+=\"uaccess\"" \
        '# Launcher firmware flash (WebUSB): STM32 ROM DFU bootloader the board re-enumerates as' \
        "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"$DFU_VID\", ATTRS{idProduct}==\"$DFU_PID\", TAG+=\"uaccess\""
end

# `command` on both: fish ships functions/diff.fish, and a user hook must not sit in this path
function _sha -d 'Print the sha256 of a file, or nothing when it cannot be read' --argument-names f
    command sha256sum -- $f 2>/dev/null | string sub -l 64
end

function _diff -d 'Print a unified diff to stderr when diffutils is installed' --argument-names old new
    command -q diff; and command diff -u -- $old $new >&2
    return 0
end

function _backup -d 'Copy the installed rule aside, with sudo when unreadable' --argument-names dst bak
    install -m 0644 -- $dst $bak 2>/dev/null; and return 0
    sudo install -m 0600 -o (id -u) -g (id -g) -- $dst $bak
end

function _write_rule -d 'Keep an identical file, back up a differing one' --argument-names src dst
    # a run killed between install and mv leaves a root-owned .tmp; udev ignores it
    test -e $dst.tmp; and sudo rm -f -- $dst.tmp; and _msg INFO "removed a stale $dst.tmp"
    set -l want (_sha $src)
    set -l have ''
    test -f $dst; and set have (_sha $dst)
    if test -n "$have"; and test "$have" = "$want"
        _msg OK "$dst already current"
        return 0
    end
    if test -e $dst
        mkdir -p -m 0700 -- $STATE_DIR; or _die 1 "cannot create $STATE_DIR"
        set -l bak $STATE_DIR/(date +%Y%m%dT%H%M%S)-$RULE.bak
        _backup $dst $bak; or _die 1 "backup failed: $bak"
        _msg INFO "existing $RULE backed up to $bak; diff (installed -> new):"
        _diff $bak $src
    end
    if not sudo install -m 0644 -- $src $dst.tmp; or not sudo mv -T -- $dst.tmp $dst
        sudo rm -f -- $dst.tmp
        _die 1 "write failed: $dst"
    end
    _msg OK "wrote $dst (0644)"
end

# ── PREFLIGHT AND DRY-RUN ──
function _preflight -d 'Refuse root and missing dependencies; gate udev >= 258' --argument-names mode
    command -q id; or _die 3 'id not found'
    test (id -u) -ne 0; or _die 2 'run as your desktop user, not root'
    command -q udevadm; or _die 3 'udevadm not found'
    test -d $SYSFS/bus/usb/devices; or _die 3 "no USB sysfs under $SYSFS"
    test -d $RULES_DIR; or _die 3 "missing $RULES_DIR"
    test -e $SEAT_LATE; or _msg WARN "$SEAT_LATE missing: nothing would apply the uaccess ACL"
    test "$mode" = install; or return 0
    command -q sudo; or _die 3 'sudo not found'
    set -l ver (udevadm --version | string match -r -- '^[0-9]+')
    test -n "$ver"; and test $ver -ge 258; or _die 3 "udevadm test -D needs systemd >= 258 (found: $ver)"
end

# the queued builtin is the proof that the candidate file sorts before 73-seat-late.rules
function _dry_run -d 'Prove a rules dir tags uaccess and queues the builtin' --argument-names node extra
    set -l opts --json=short
    test -n "$extra"; and set -a opts -D $extra
    set -l json (sudo udevadm test $opts $node 2>/dev/null | string collect)
    set -l why
    test -n "$json"; or set why 'udevadm test produced no JSON'
    test -n "$why"; or string match -qr -- '"tags":\[[^]]*"uaccess"' $json; or set why 'no uaccess tag'
    test -n "$why"; or string match -qr -- '"command":"uaccess"' $json; or set why 'no uaccess builtin'
    if test -n "$why"
        _msg FAIL "$node: $why"
        return 1
    end
    _msg OK "$node: uaccess tag set and ACL builtin queued"
end

# ── MODES ──
function _inventory -d 'Print the Keychron, DFU and hidraw devices present'
    set -l usb (_usb_list $KC_VID)
    set -l dfu (_usb_list $DFU_VID $DFU_PID)
    test (count $usb) -gt 0; or test (count $dfu) -gt 0; or _msg WARN $NODEV
    for u in $usb
        set -l f (string split -- '|' $u)
        _msg INFO "usb $f[1] $f[2] ($f[3]) bus $f[4] dev $f[5]"
    end
    for u in $dfu
        set -l f (string split -- '|' $u)
        _msg INFO "dfu $f[1] $f[2] ($f[3]) bus $f[4] dev $f[5]"
    end
    test (count $usb) -gt 0; or test (count $dfu) -eq 0; or _msg INFO $INDFU
    for h in (_hidraw_list)
        set -l f (string split -- '|' $h)
        _msg INFO "hidraw $f[1] pid $f[2] ($f[3])"
    end
end

function _check -d 'Compare the installed rule with the expected text; return 4 on drift'
    _inventory
    set -l dst $RULES_DIR/$RULE
    _rule_text >$_TMP/$RULE
    if not test -e $dst
        _msg WARN "$dst missing; --install writes:"
        cat -- $_TMP/$RULE >&2
        return 4
    end
    set -l have (_sha $dst)
    set -l want (_sha $_TMP/$RULE)
    # an unquoted empty substitution collapses the operand list and `test` falls through
    if test (string length -- "$have") -ne 64
        _msg WARN "$dst is not a readable regular file"
        return 4
    end
    if test "$have" != "$want"
        _msg WARN "$dst differs from the expected rule (installed -> expected):"
        _diff $dst $_TMP/$RULE
        return 4
    end
    _msg OK "$dst matches the expected rule"
end

function _install -d 'Dry-run the candidate, write it, reload udev, re-add the live nodes, verify'
    set -l lockdir /tmp
    test -n "$XDG_RUNTIME_DIR"; and set lockdir $XDG_RUNTIME_DIR
    set -l lock $lockdir/keychron-udev.lock
    mkdir -- $lock 2>/dev/null; or _die 1 "another run holds $lock (rmdir it if no run is active)"
    set -g _LOCK $lock
    _inventory
    sudo -v; or _die 3 'sudo authentication failed'
    _rule_text >$_TMP/$RULE
    set -l nodes (_hidraw_list | string split -f1 -- '|') (_dfu_nodes)
    test (count $nodes) -gt 0; or _msg WARN $NONODE
    for n in $nodes
        _dry_run $n $_TMP; or _die 1 'candidate rule failed the udevadm dry-run; nothing written'
    end
    _write_rule $_TMP/$RULE $RULES_DIR/$RULE
    sudo udevadm control --reload; or _die 1 'udevadm control --reload failed'
    if test (count $nodes) -gt 0
        sudo udevadm trigger --action=add --settle $nodes; or _die 1 'udevadm trigger failed'
        _msg OK "re-added $nodes"
    end
    _verify
    _msg INFO 'next: https://launcher.keychron.com/ in Chrome, Connect, Firmware Update'
end

function _verify -d 'Check read-write access on every Keychron node; exit 5 on failure'
    set -l fail 0
    set -l targets
    for h in (_hidraw_list)
        set -l f (string split -- '|' $h)
        set -a targets "$f[1]|$f[3]"
    end
    for n in (_dfu_nodes)
        set -a targets "$n|STM32 DFU bootloader"
    end
    test (count $targets) -gt 0; or _msg WARN 'no Keychron hidraw node or STM32 DFU device present'
    for t in $targets
        set -l f (string split -- '|' $t)
        if test -r $f[1]; and test -w $f[1]
            _msg OK "$f[1] rw for $USER ($f[2])"
        else
            _msg FAIL "$f[1] not accessible for $USER ($f[2])"
            set fail 1
        end
    end
    test $fail -eq 0; or _die 5 'access not live: replug the device, or run --install'
    command -q getfacl; or return 0
    for t in $targets
        set -l node (string split -f1 -- '|' $t)
        for l in (getfacl -p $node 2>/dev/null | string match -r -- '^user:[^:]+:.+')
            _msg INFO "$node acl $l"
        end
    end
    # the ACL display is informational: an entry-less node must not become exit 1
    return 0
end

# ── MAIN ──
argparse -n keychron-udev -x check,install,verify h/help V/version c/check i/install v/verify -- $argv; or exit 2
if set -q _flag_help
    _usage
    exit 0
end
if set -q _flag_version
    echo "keychron-udev.fish $VERSION"
    exit 0
end
test (count $argv) -eq 0; or _die 2 "unexpected argument: $argv[1]"
set -l mode check
set -q _flag_install; and set mode install
set -q _flag_verify; and set mode verify
_preflight $mode
_log_open $mode
set -g _TMP (mktemp -d --tmpdir keychron-udev.XXXXXX); or _die 1 'mktemp failed'
switch $mode
    case install
        _install
    case verify
        _verify
    case '*'
        _check
end
set -l rc $status
test -n "$_LOG"; and _msg INFO "log: $_LOG"
exit $rc
