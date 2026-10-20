#!/usr/bin/env bash
# Applies the last-chosen OpenRGB profile at login and after every resume from suspend,
# via the resident headless server (openrgb-server.service). Run by openrgb-profile.service.
STATE="${XDG_CONFIG_HOME:-$HOME/.config}/openrgb-current-profile"   # written by openrgb-set-profile; default purple
SDK="$HOME/.local/bin/openrgb-sdk.py"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/openrgb-profile.lock"

log() { echo "[$(date +%T)] $*"; }

current_profile() { local p; p="$(cat "$STATE" 2>/dev/null)"; echo "${p:-purple}"; }

apply() {
    # $1 = seconds to wait first (let USB/SMBus devices come back)
    sleep "$1"
    (
        flock -w 180 9 || { log "could not get lock"; exit 1; }
        if "$SDK" wait 150; then
            PROFILE="$(current_profile)"
            log "server ready, loading '$PROFILE'"
            "$SDK" load "$PROFILE" 5 && log "loaded"
            # second pass: the motherboard controller can re-initialise a bit after resume/boot
            sleep 15
            PROFILE="$(current_profile)"   # re-read: you may have switched in the meantime
            "$SDK" load "$PROFILE" 5 && log "second pass done ($PROFILE)"
        else
            log "server not ready after 150 s"
        fi
    ) 9>"$LOCK"
}

apply 3 &   # login / service start

dbus-monitor --system \
    "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null |
while read -r line; do
    case "$line" in
        *member=PrepareForSleep*) armed=1 ;;
        *"boolean true"*)  armed=0 ;;                       # going to sleep
        *"boolean false"*) if [ "${armed:-0}" = 1 ]; then   # woke up
                               armed=0; log "resumed from suspend: restarting server"
                               systemctl --user restart openrgb-server.service
                               apply 5 &
                           fi ;;
    esac
done
