#!/usr/bin/env bash
# OpenRGB setup for Linux: manual installer. NOT run by `stow .`, run it yourself on machines where you want it.
#
#   ./openrgb/setup.sh                 install (symlinks + user services; asks before each sudo step)
#   ./openrgb/setup.sh status          show what is installed / missing
#   ./openrgb/setup.sh launchers       add a menu entry ("OpenRGB: <Name>") per new profile, remove those of deleted ones
#   ./openrgb/setup.sh sync            copy OpenRGB-written config files back into the repo, then re-link
#   ./openrgb/setup.sh uninstall       remove the symlinks and user services (system files are left alone)
#
# Options:  -y/--yes  answer yes to every question     -n/--dry-run  only print what would be done
#           --no-system  skip the sudo steps (udev rules, kernel modules, boot parameter)
#           --no-services  do not touch systemd user services
#
# Everything the repo provides is *symlinked*, so a `git pull` updates the live setup. Existing real files
# in the way are moved to ~/.local/state/openrgb-setup/backup-<timestamp>/ first.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/openrgb-setup/backup-$(date +%Y%m%d-%H%M%S)"

APPIMAGE_URL="https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_1.1/OpenRGB_1.1_x86_64_8e16de2.AppImage"
SERVICES=(openrgb-server.service openrgb-profile.service openrgb-profiles-watch.path)
PROFILES_DIR="$REPO/config/profiles"
APPS_DIR="$REPO/applications"

CMD=install; ASSUME_YES=0; DRY_RUN=0; DO_SYSTEM=1; DO_SERVICES=1
for arg in "$@"; do
    case "$arg" in
        install|status|launchers|sync|uninstall) CMD="$arg" ;;
        -y|--yes) ASSUME_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        --no-system) DO_SYSTEM=0 ;;
        --no-services) DO_SERVICES=0 ;;
        -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
        *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------- helpers
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_dim=$'\e[2m'; c_off=$'\e[0m'
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '  %sok%s    %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %swarn%s  %s\n' "$c_warn" "$c_off" "$*"; }
err()  { printf '  %sERR%s   %s\n' "$c_err" "$c_off" "$*" >&2; }
note() { printf '  %s%s%s\n' "$c_dim" "$*" "$c_off"; }

run() {                       # run a command, or just print it with --dry-run
    if [ "$DRY_RUN" = 1 ]; then printf '  %s+ %s%s\n' "$c_dim" "$*" "$c_off"; return 0; fi
    "$@"
}

ask() {                       # ask "question"  -> returns 0 on yes
    [ "$ASSUME_YES" = 1 ] && return 0
    [ -t 0 ] || return 1
    local reply; read -r -p "  ? $1 [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

udev_rules_file() {           # path of the first OpenRGB rules file in the usual places (compgen: no error when a glob is empty)
    local g; for g in /etc/udev/rules.d/*openrgb* /usr/lib/udev/rules.d/*openrgb* /lib/udev/rules.d/*openrgb*; do
        compgen -G "$g" | head -n1 | grep . && return 0
    done
    return 1
}
udev_rules_present() { udev_rules_file >/dev/null; }

# Report-only: RGB controllers that a userspace program has claimed through usbfs. While a device is in that state
# (seen with Linuity's root daemon holding the Gigabyte 048d:5702 controller) OpenRGB cannot use it. OpenRGB itself
# does not leave devices like that, so any hit points to another program. Nothing is changed here.
check_usb_claims() {
    step "RGB USB controllers held by another program"
    local sys="${OPENRGB_SETUP_SYSFS:-/sys}"     # overridable for testing only
    local rules; rules="$(udev_rules_file)"
    local found=0 iface dev vid pid name node holders p
    for iface in "$sys"/bus/usb/drivers/usbfs/*:*; do
        [ -e "$iface" ] || continue
        dev="$(readlink -f "$iface/..")"
        vid="$(cat "$dev/idVendor" 2>/dev/null)"; pid="$(cat "$dev/idProduct" 2>/dev/null)"
        [ -n "$vid" ] || continue
        # only devices OpenRGB knows about (if the rules file is missing, report every claimed device)
        if [ -n "$rules" ] && ! grep -q "idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\"" "$rules"; then continue; fi
        found=1
        name="$(cat "$dev/product" 2>/dev/null)"
        node="$(printf '/dev/bus/usb/%03d/%03d' "$(cat "$dev/busnum")" "$(cat "$dev/devnum")")"
        warn "$vid:$pid ${name:+($name) }interface $(basename "$iface") is claimed by a userspace program: OpenRGB cannot use it"
        holders=""
        for p in /proc/[0-9]*; do                 # only your own processes are visible without root
            ls -l "$p/fd" 2>/dev/null | grep -q " $node\$" && holders="$holders $(basename "$p")($(cat "$p/comm" 2>/dev/null))"
        done
        if [ -n "$holders" ]; then note "held by:$holders"
        else note "holder not visible without root, check with:  sudo fuser -v $node"; fi
        note "stop/remove that program, then reset the device:"
        note "  echo 0 | sudo tee /sys/bus/usb/devices/$(basename "$dev")/authorized; sleep 1; echo 1 | sudo tee /sys/bus/usb/devices/$(basename "$dev")/authorized"
    done
    [ "$found" = 0 ] && ok "none (no RGB controller is claimed by another program)"
    return 0
}

# ---------------------------------------------------------------- guards
if [ "$(uname -s)" != "Linux" ]; then
    echo "This setup is for Linux only (detected: $(uname -s)). Nothing to do." >&2
    exit 1
fi

# Config dir of OpenRGB: the Flatpak one if that is the only install, else the native one.
openrgb_config_dir() {
    [ -n "${OPENRGB_CONFIG_DIR:-}" ] && { echo "$OPENRGB_CONFIG_DIR"; return; }
    if have flatpak && flatpak info org.openrgb.OpenRGB >/dev/null 2>&1 \
        && ! have openrgb && ! ls "$HOME"/Applications/OpenRGB*.AppImage >/dev/null 2>&1; then
        echo "$HOME/.var/app/org.openrgb.OpenRGB/config/OpenRGB"
    else
        echo "$CONFIG_HOME/OpenRGB"
    fi
}
OPENRGB_CFG="$(openrgb_config_dir)"

# source (inside the repo) | destination (live location)
mappings() {
    local f
    for f in "$REPO"/bin/*;          do echo "$f|$HOME/.local/bin/$(basename "$f")"; done
    for f in "$REPO"/systemd/*.service "$REPO"/systemd/*.path; do echo "$f|$CONFIG_HOME/systemd/user/$(basename "$f")"; done
    for f in "$REPO"/applications/*.desktop; do echo "$f|$HOME/.local/share/applications/$(basename "$f")"; done
    echo "$REPO/icons/openrgb.png|$HOME/.local/share/icons/hicolor/128x128/apps/openrgb.png"
    echo "$REPO/fontconfig/fonts.conf|$CONFIG_HOME/openrgb-fontconfig/fonts.conf"
    config_mappings
}
config_mappings() {           # the files OpenRGB itself reads and writes
    echo "$REPO/config/profiles|$OPENRGB_CFG/profiles"
    echo "$REPO/config/Configuration.json|$OPENRGB_CFG/Configuration.json"
}

is_link_to() { [ -L "$2" ] && [ "$(readlink -f "$2")" = "$(readlink -f "$1")" ]; }

backup() {
    run mkdir -p "$BACKUP_DIR"
    run mv "$1" "$BACKUP_DIR/$(echo "$1" | tr '/' '_')"
    warn "existing $1 moved to $BACKUP_DIR"
}

link() {                      # link <repo file> <live path>
    local src="$1" dst="$2"
    if is_link_to "$src" "$dst"; then ok "already linked  $dst"; return; fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then backup "$dst"; fi
    run mkdir -p "$(dirname "$dst")"
    run ln -s "$src" "$dst" && ok "linked  $dst"
}

# ---------------------------------------------------------------- profile launchers
# Every launcher carries "X-OpenRGB-Profile=<name>", which is how a profile is matched to its menu entry.
profile_names() { local f; for f in "$PROFILES_DIR"/*.json; do [ -e "$f" ] && basename "$f" .json; done; }
launcher_of() { grep -l -x -F "X-OpenRGB-Profile=$1" "$APPS_DIR"/*.desktop 2>/dev/null | head -n1; }
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }

make_launcher() {             # make_launcher <profile name>: writes applications/openrgb-<slug>.desktop and links it
    local name="$1" file
    case "$name" in *[\'\"\`\$\\]*)
        warn "skipped '$name': quotes, \$, \` or \\ in a profile name are not supported in launchers"; return 1 ;;
    esac
    [ -n "$(slug "$name")" ] || { warn "skipped '$name': no usable characters for a file name"; return 1; }
    file="$APPS_DIR/openrgb-$(slug "$name").desktop"
    if [ -e "$file" ]; then warn "skipped '$name': $(basename "$file") already exists for another profile"; return 1; fi
    if [ "$DRY_RUN" = 1 ]; then note "(dry run) would create applications/$(basename "$file") for '$name'"; return 0; fi
    # Exec: "\\$HOME" is the desktop-entry spelling of a literal $HOME inside a quoted argument
    cat > "$file" <<EOF
[Desktop Entry]
Type=Application
Name=OpenRGB: ${name^}
Comment=Apply the "$name" OpenRGB profile
Exec=sh -c "\\\\\$HOME/.local/bin/openrgb-set-profile '$name'"
Icon=openrgb
Terminal=false
Categories=Utility;
X-OpenRGB-Profile=$name
EOF
    if have desktop-file-validate && ! desktop-file-validate "$file" >/dev/null 2>&1; then
        err "generated $(basename "$file") is not valid, removing it"; rm -f "$file"; return 1
    fi
    ok "created applications/$(basename "$file") for '$name'"
    link "$file" "$HOME/.local/share/applications/$(basename "$file")"
}

do_launchers() {
    step "Profile launchers (menu entries)"
    local name f created=0
    while IFS= read -r name; do
        f="$(launcher_of "$name")"
        if [ -n "$f" ]; then ok "'$name' -> applications/$(basename "$f")"; continue; fi
        make_launcher "$name" && created=$((created + 1))
    done < <(profile_names)
    # launchers whose profile is gone: remove the repo file and its menu link (only launchers tagged with
    # X-OpenRGB-Profile, so the plain "OpenRGB" entry is never touched)
    local removed=0 live
    for f in "$APPS_DIR"/*.desktop; do
        [ -e "$f" ] || continue
        name="$(sed -n 's/^X-OpenRGB-Profile=//p' "$f")"
        [ -n "$name" ] && [ ! -e "$PROFILES_DIR/$name.json" ] || continue
        live="$HOME/.local/share/applications/$(basename "$f")"
        is_link_to "$f" "$live" && run rm "$live"
        if [ "$DRY_RUN" = 1 ]; then note "(dry run) would remove applications/$(basename "$f") (profile '$name' no longer exists)"
        else rm "$f" && ok "removed applications/$(basename "$f") (profile '$name' no longer exists)"; fi
        removed=$((removed + 1))
    done
    if [ $((created + removed)) -gt 0 ]; then
        have update-desktop-database && run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
        note "$created launcher(s) created, $removed removed. Commit the changes in applications/ together with the profiles."
    fi
    return 0
}

profiles_report() {           # status: launcher + git state per profile
    step "Profiles"
    local name f state
    while IFS= read -r name; do
        f="$(launcher_of "$name")"
        state="$(git -C "$REPO" status --porcelain -- "config/profiles/$name.json" 2>/dev/null)"
        if [ -n "$f" ] && [ -z "$state" ]; then ok "$name  (launcher, committed)"; continue; fi
        warn "$name  ($([ -n "$f" ] && echo launcher || echo 'NO launcher: run setup.sh launchers'), $([ -z "$state" ] && echo committed || echo 'NOT committed to dotfiles'))"
    done < <(profile_names)
    git -C "$REPO" status --porcelain -- config/profiles 2>/dev/null | grep '^ D\|^D ' | sed 's#.*/##' | while read -r f; do
        warn "deleted profile not committed yet: $f"
    done
    return 0
}

# ---------------------------------------------------------------- install steps
find_openrgb() {              # same lookup order as bin/openrgb-run
    have openrgb && return 0
    ls "$HOME"/Applications/OpenRGB*.AppImage >/dev/null 2>&1 && return 0
    have flatpak && flatpak info org.openrgb.OpenRGB >/dev/null 2>&1 && return 0
    return 1
}

install_binary() {
    step "OpenRGB itself"
    if find_openrgb; then ok "OpenRGB found"; return; fi
    warn "OpenRGB not found (no 'openrgb' in PATH, no ~/Applications/OpenRGB*.AppImage, no Flatpak)"
    note "Install it from your distro / Flatpak (org.openrgb.OpenRGB), or let this script fetch the 1.1 AppImage."
    if [ "$(uname -m)" != "x86_64" ]; then warn "the bundled download URL is x86_64 only; install OpenRGB manually"; return; fi
    if ask "Download the OpenRGB 1.1 AppImage from Codeberg into ~/Applications?"; then
        run mkdir -p "$HOME/Applications"
        local out="$HOME/Applications/$(basename "$APPIMAGE_URL")"
        if run curl -fL --progress-bar -o "$out" "$APPIMAGE_URL"; then run chmod +x "$out"; ok "downloaded $out"
        else err "download failed"; fi
        note "If it does not start, your distro may need libfuse2, or run it with --appimage-extract-and-run."
    fi
}

install_links() {
    step "Symlinks"
    while IFS='|' read -r src dst; do link "$src" "$dst"; done < <(mappings)
    have update-desktop-database && run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
    have gtk-update-icon-cache && run gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin is not in your PATH (the launchers use absolute paths, so they still work)";; esac
    return 0
}

install_services() {
    step "systemd user services"
    have systemctl || { warn "systemctl not found, skipping"; return; }
    if ! systemctl --user show-environment >/dev/null 2>&1; then warn "no systemd user session reachable right now, skipping"; return; fi
    run systemctl --user daemon-reload
    run systemctl --user enable --now "${SERVICES[@]}" && ok "enabled + started: ${SERVICES[*]}"
    note "If you changed a script and want it picked up now: systemctl --user restart ${SERVICES[*]}"
}

sys_udev_rules() {
    step "System: udev rules (lets your user control the devices without root)"
    if udev_rules_present; then
        ok "an OpenRGB udev rules file is already installed"; return
    fi
    ask "Generate the rules with OpenRGB and install them to /etc/udev/rules.d/60-openrgb.rules (sudo)?" || { note "skipped"; return; }
    local tmp; tmp="$(mktemp)"
    if [ "$DRY_RUN" = 1 ]; then note "(dry run) would generate rules with: openrgb-run --print-udev-rules"; rm -f "$tmp"; return; fi
    "$REPO/bin/openrgb-run" --print-udev-rules > "$tmp" 2>/dev/null
    # never install an empty/garbage file (an earlier attempt once installed a "404 Not found" page)
    if [ "$(wc -c < "$tmp")" -lt 10000 ] || ! grep -q 'uaccess' "$tmp"; then
        err "OpenRGB did not produce a valid rules file; install OpenRGB first, then re-run"; rm -f "$tmp"; return
    fi
    sudo install -m 0644 "$tmp" /etc/udev/rules.d/60-openrgb.rules && sudo udevadm control --reload-rules && sudo udevadm trigger \
        && ok "installed /etc/udev/rules.d/60-openrgb.rules (log out and in again to be sure)"
    rm -f "$tmp"
}

sys_modules() {
    step "System: kernel modules for I2C/SMBus (RAM, some motherboards/GPUs)"
    local mods="i2c-dev"
    if grep -qi 'AuthenticAMD' /proc/cpuinfo; then mods="$mods i2c-piix4"; elif grep -qi 'GenuineIntel' /proc/cpuinfo; then mods="$mods i2c-i801"; fi
    local want; want="$(printf '%s\n' $mods)"
    if [ -f /etc/modules-load.d/openrgb.conf ] && [ "$(cat /etc/modules-load.d/openrgb.conf)" = "$want" ]; then
        ok "/etc/modules-load.d/openrgb.conf already up to date ($mods)"; return
    fi
    ask "Load '$mods' at every boot via /etc/modules-load.d/openrgb.conf (sudo)?" || { note "skipped"; return; }
    if [ "$DRY_RUN" = 1 ]; then note "(dry run) would write: $mods"; return; fi
    printf '%s\n' $mods | sudo tee /etc/modules-load.d/openrgb.conf >/dev/null \
        && sudo modprobe -a $mods 2>/dev/null; ok "wrote /etc/modules-load.d/openrgb.conf ($mods)"
}

sys_kernel_arg() {
    step "System: kernel parameter acpi_enforce_resources=lax (only if the SMBus is blocked)"
    if grep -q 'acpi_enforce_resources=lax' /proc/cmdline; then ok "already on the kernel command line"; return; fi
    local hint="not needed unless OpenRGB cannot see your RAM / motherboard SMBus devices"
    if { journalctl -k -b 2>/dev/null || dmesg 2>/dev/null; } | grep -q 'conflicts with OpRegion'; then
        hint="RECOMMENDED here: the kernel log shows an ACPI resource conflict on the SMBus (this was the case on the B550M AORUS ELITE)"
    fi
    note "$hint"
    ask "Add acpi_enforce_resources=lax to the boot parameters (sudo, needs a reboot)?" || { note "skipped"; return; }
    if have rpm-ostree; then
        run sudo rpm-ostree kargs --append-if-missing=acpi_enforce_resources=lax && ok "added via rpm-ostree (reboot to apply)"
    elif [ -f /etc/default/grub ] && grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
        run sudo cp /etc/default/grub /etc/default/grub.openrgb.bak
        run sudo sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 acpi_enforce_resources=lax"/' /etc/default/grub
        if have update-grub; then run sudo update-grub
        elif have grub2-mkconfig; then run sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        elif have grub-mkconfig; then run sudo grub-mkconfig -o /boot/grub/grub.cfg
        else warn "could not find update-grub/grub2-mkconfig: regenerate your GRUB config manually"; fi
        ok "edited /etc/default/grub (backup: /etc/default/grub.openrgb.bak). Reboot to apply."
    else
        warn "unknown bootloader setup. Add acpi_enforce_resources=lax to your kernel command line manually."
    fi
}

do_install() {
    install_binary
    install_links
    do_launchers
    [ "$DO_SERVICES" = 1 ] && install_services
    if [ "$DO_SYSTEM" = 1 ]; then
        have sudo || { warn "sudo not found, skipping system steps"; return; }
        sys_udev_rules; sys_modules; sys_kernel_arg
    fi
    step "Done"
    note "Menu entries: 'OpenRGB' plus one 'OpenRGB: <Profile>' per profile. New profile? Run: $REPO/setup.sh launchers"
    note "Check everything with: $REPO/setup.sh status"
}

# ---------------------------------------------------------------- status / sync / uninstall
do_status() {
    step "OpenRGB binary"; if find_openrgb; then ok "found"; else err "not found"; fi
    step "Symlinks"
    while IFS='|' read -r src dst; do
        if is_link_to "$src" "$dst"; then ok "$dst"
        elif [ -e "$dst" ]; then warn "$dst exists but is NOT linked to the repo (run 'sync' to pull it into the repo, or 'install' to relink)"
        else err "$dst missing"; fi
    done < <(mappings)
    step "Services"
    for s in "${SERVICES[@]}"; do
        printf '  %-28s enabled=%-9s active=%s\n' "$s" "$(systemctl --user is-enabled "$s" 2>&1)" "$(systemctl --user is-active "$s" 2>&1)"
    done
    step "System"
    udev_rules_present && ok "udev rules present" || warn "udev rules missing"
    [ -f /etc/modules-load.d/openrgb.conf ] && ok "modules-load: $(tr '\n' ' ' < /etc/modules-load.d/openrgb.conf)" || warn "no /etc/modules-load.d/openrgb.conf"
    grep -q 'acpi_enforce_resources=lax' /proc/cmdline && ok "kernel arg acpi_enforce_resources=lax active" || note "kernel arg acpi_enforce_resources=lax not set (only needed if the SMBus is blocked)"
    check_usb_claims
    profiles_report
    step "Current profile"; note "$(cat "$CONFIG_HOME/openrgb-current-profile" 2>/dev/null || echo 'purple (default)')"
}

do_sync() {
    step "Sync OpenRGB-written config back into the repo"
    local n=0
    while IFS='|' read -r src dst; do
        if [ -e "$dst" ] && ! is_link_to "$src" "$dst"; then
            if [ -d "$dst" ]; then run cp -a "$dst"/. "$src"/; else run cp -a "$dst" "$src"; fi
            ok "copied $dst -> repo"; n=$((n+1))
        fi
    done < <(config_mappings)
    [ "$n" = 0 ] && ok "nothing to sync (config files are already symlinks into the repo)"
    note "Review with: git -C $REPO status ; then re-link with: $REPO/setup.sh install --no-system --no-services"
}

do_uninstall() {
    step "Remove user services"
    if [ "$DO_SERVICES" = 1 ] && have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
        run systemctl --user disable --now "${SERVICES[@]}" 2>/dev/null; ok "services disabled"
    fi
    step "Remove symlinks (only those pointing into this repo)"
    while IFS='|' read -r src dst; do
        if is_link_to "$src" "$dst"; then run rm "$dst" && ok "removed $dst"; fi
    done < <(mappings)
    run systemctl --user daemon-reload 2>/dev/null
    note "Left alone: /etc/udev/rules.d/60-openrgb.rules, /etc/modules-load.d/openrgb.conf, kernel parameters, ~/Applications/*.AppImage."
}

case "$CMD" in
    install)   do_install ;;
    status)    do_status ;;
    launchers) do_launchers ;;
    sync)      do_sync ;;
    uninstall) do_uninstall ;;
esac
