#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
#
#  awww for static images + transitions
#  mpvpaper for animated (mp4/gif) wallpapers
#
#   - per-monitor wallpaper picker via rofi (auto-skips on single monitor)
#   - smooth transitions in BOTH directions (image <-> video)
#   - persistent per-monitor state, restorable on login with `--restore`
#
#  Usage:
#    wallpaper-switcher.sh [WALLPAPER_DIR]   # interactive picker
#    wallpaper-switcher.sh --restore         # re-apply saved wallpapers
# =============================================================================

# =============================================================================
# Configure your own variables for themes / transitions
WALLPAPER_DIR_DEFAULT="$HOME/Wallpapers"
WALLPAPER_THEME="$HOME/.config/rofi/wallpapers.rasi"
MONITOR_THEME="$HOME/.config/rofi/style7.rasi"
AWW_FPS="240"

TRANSITION_TYPE="grow"
TRANSITION_POS="0.5,0.5"
TRANSITION_DURATION="1.1"
# Configure your own variables for themes / transitions
# =============================================================================

# =============================================================================
# You most probably don't have to touch these
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-switcher"
mkdir -p "$STATE_DIR"

# safety cap when waiting for mpvpaper to die after pkill
MPV_KILL_TIMEOUT="2.0"
# =============================================================================

# Helper functions
die_please() {
    notify-send "Wallpaper" "$1" 2>/dev/null || true
    echo "$1" >&2
    exit 1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

state_file_for() {
    printf '%s/last-%s' "$STATE_DIR" "${1//[^A-Za-z0-9_-]/_}"
}

save_state() {
    printf '%s\n' "$2" >"$(state_file_for "$1")"
}

read_state() {
    local f
    f="$(state_file_for "$1")"
    [[ -f "$f" ]] && cat "$f" || true
}

# capture a frame from video $1 into $2 (at timestamp $3, default 0.2s)
# 2k resolution by default, change 2560 -> 1920 for 1080p
capture_frame() {
    local ts="${3:-0.2}"
    ffmpeg -y -loglevel quiet \
        -ss "$ts" \
        -i "$1" \
        -vframes 1 \
        -vf "scale=2560:-1" \
        "$2"
}

is_video() {
    case "${1##*.}" in
    mp4 | MP4 | gif | GIF | mkv | MKV | webm | WEBM) return 0 ;;
    *) return 1 ;;
    esac
}

ensure_awww_daemon() {
    if ! awww query >/dev/null 2>&1; then
        awww-daemon >/dev/null 2>&1 &
        for _ in {1..20}; do
            awww query >/dev/null 2>&1 && break
            sleep 0.1
        done
    fi
}

# Kill mpvpaper on a monitor and BLOCK until it's truly dead.
# pkill returns immediately, but a still-alive mpvpaper kept
# painting over the wallpaper layer and hiding the awww transition
kill_mpvpaper() {
    local pattern="mpvpaper $1"
    pgrep -f "$pattern" >/dev/null 2>&1 || return 0
    pkill -f "$pattern" 2>/dev/null || true

    local waited="0.0"
    while pgrep -f "$pattern" >/dev/null 2>&1; do
        sleep 0.05
        waited=$(awk -v w="$waited" 'BEGIN{printf "%.2f", w+0.05}')
        if awk -v w="$waited" -v t="$MPV_KILL_TIMEOUT" 'BEGIN{exit !(w>=t)}'; then
            pkill -9 -f "$pattern" 2>/dev/null || true
            sleep 0.1
            break
        fi
    done
}

# Lay down a "from" frame on the wallpaper layer with NO animation, so the
# subsequent awww transition has a correct starting image. Used when switching
# FROM a video to an image
seed_awww_frame() {
    local monitor="$1" img="$2"
    [[ -f "$img" ]] || return 1
    awww img "$img" --outputs "$monitor" --transition-type none
}

# Usage: apply_wallpaper <monitor> <full_path> [interactive|restore]
apply_wallpaper() {
    local monitor="$1" full_path="$2" mode="${3:-interactive}"
    local ext="${full_path##*.}"
    ext="${ext,,}"
    [[ -f "$full_path" ]] || die_please "File not found: $full_path"

    local safe="${monitor//[^A-Za-z0-9_-]/_}"
    local bridge="/tmp/wallpaper-bridge-${safe}.jpg"

    # what is currently on this monitor?
    local prev_video=""
    if pgrep -f "mpvpaper $monitor" >/dev/null 2>&1; then
        prev_video="$(read_state "$monitor")"
        # only trust it if it actually is a video file that still exists
        if [[ -z "$prev_video" ]] || ! is_video "$prev_video" || [[ ! -f "$prev_video" ]]; then
            prev_video=""
        fi
    fi

    ensure_awww_daemon

    case "$ext" in
    png | jpg | jpeg | webp)
        if [[ "$mode" == "restore" ]]; then
            kill_mpvpaper "$monitor"
            awww img "$full_path" --outputs "$monitor" --transition-type none
        else
            if [[ -n "$prev_video" ]]; then
                # VIDEO -> IMAGE: capture the outgoing video's current frame,
                # seed it as the "from", then kill the video and grow into the
                # new image. Order matters: capture & seed BEFORE killing so
                # there's never a black gap.
                capture_frame "$prev_video" "$bridge"
                seed_awww_frame "$monitor" "$bridge" || true
                kill_mpvpaper "$monitor"
            fi
            awww img "$full_path" \
                --outputs "$monitor" \
                --transition-type "$TRANSITION_TYPE" \
                --transition-pos "$TRANSITION_POS" \
                --transition-duration "$TRANSITION_DURATION" \
                --transition-fps "$AWW_FPS"
        fi
        rm -f "$bridge"
        ;;

    gif | mp4 | mkv | webm)
        if [[ "$mode" == "restore" ]]; then
            kill_mpvpaper "$monitor"
            mpvpaper "$monitor" -o "no-audio loop" "$full_path" >/dev/null 2>&1 &
        else
            # -> VIDEO (from image OR video):
            # 1. capture incoming video's first frame
            # 2. if leaving a video, seed the outgoing frame as the "from"
            # 3. kill outgoing video, WAIT for it to die
            # 4. grow current wallpaper -> incoming first frame
            # 5. once the transition lands, start mpvpaper on top
            capture_frame "$full_path" "$bridge"

            if [[ -n "$prev_video" ]]; then
                local fromframe="/tmp/wallpaper-from-${safe}.jpg"
                capture_frame "$prev_video" "$fromframe"
                seed_awww_frame "$monitor" "$fromframe" || true
                rm -f "$fromframe"
            fi

            kill_mpvpaper "$monitor"

            awww img "$bridge" \
                --outputs "$monitor" \
                --transition-type "$TRANSITION_TYPE" \
                --transition-pos "$TRANSITION_POS" \
                --transition-duration "$TRANSITION_DURATION" \
                --transition-fps "$AWW_FPS"

            sleep "$TRANSITION_DURATION"

            mpvpaper "$monitor" -o "no-audio loop" "$full_path" >/dev/null 2>&1 &
        fi
        rm -f "$bridge"
        ;;

    *)
        die_please "Unsupported file: $full_path"
        ;;
    esac

    save_state "$monitor" "$full_path"
}

# restore last choice on startup
do_restore() {
    ensure_awww_daemon
    local f mon path
    shopt -s nullglob
    for f in "$STATE_DIR"/last-*; do
        path="$(cat "$f")"
        [[ -n "$path" && -f "$path" ]] || continue
        mon="$(basename "$f")"
        mon="${mon#last-}"
        apply_wallpaper "$mon" "$path" restore
    done
    shopt -u nullglob
    exit 0
}

# entrypoint
for dep in awww rofi fd ffmpeg mpvpaper hyprctl pgrep; do
    have "$dep" || die_please "Missing dependency: $dep"
done

[[ "${1:-}" == "--restore" ]] && do_restore

WALLPAPER_DIR="${1:-$WALLPAPER_DIR_DEFAULT}"
[[ -d "$WALLPAPER_DIR" ]] || die_please "Wallpaper dir not found: $WALLPAPER_DIR"

mapfile -t MONITORS < <(hyprctl monitors | awk '/Monitor/ {print $2}')
[[ "${#MONITORS[@]}" -eq 0 ]] && die_please "No monitors detected"

if [[ "${#MONITORS[@]}" -eq 1 ]]; then
    MONITOR="${MONITORS[0]}"
else
    MONITOR="$(
        printf '%s\n' "${MONITORS[@]}" |
            rofi -dmenu -i -p "Select monitor" -theme "$MONITOR_THEME"
    )"
fi
[[ -z "$MONITOR" ]] && exit 0

choice="$(
    fd -t f -e png -e jpg -e jpeg -e webp -e mp4 -e gif -e mkv -e webm \
        . "$WALLPAPER_DIR" |
        sed "s|$WALLPAPER_DIR/||" |
        while read -r file; do
            printf "%s\0icon\x1fthumbnail://%s\n" "$file" "$WALLPAPER_DIR/$file"
        done |
        rofi -dmenu -i -p "Wallpaper ($MONITOR)" \
            -theme "$WALLPAPER_THEME" \
            -show-icons
)"
[[ -z "$choice" ]] && exit 0

apply_wallpaper "$MONITOR" "$WALLPAPER_DIR/$choice" interactive
