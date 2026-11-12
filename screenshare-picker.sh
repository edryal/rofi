#!/usr/bin/env bash
set -uo pipefail

PATH="${PATH:+$PATH:}/usr/bin"
shopt -u patsub_replacement 2>/dev/null

if [[ "${1:-}" == "--tab" ]]; then
    if [[ "${ROFI_RETV:-0}" == 1 ]]; then
        printf '%s' "${ROFI_INFO:-}" >"$SHARE_TMP/pick"
        exit 0
    fi

    escape() {
        local text="${1//&/&amp;}"
        text="${text//</&lt;}"
        printf '%s' "${text//>/&gt;}"
    }
    preview() { if [[ -s "$SHARE_TMP/$1.jpg" ]]; then printf '%s' "$SHARE_TMP/$1.jpg"; else printf '%s' "$2"; fi; }
    row() {
        printf '%s %s\0display\x1f%s&#10;<span size="small" alpha="70%%">%s</span>\x1ficon\x1f%s\x1finfo\x1f%s\n' \
            "$1" "$2" "$(escape "$1")" "$(escape "$2")" "$3" "$4"
    }

    printf '\0no-custom\x1ftrue\n\0markup-rows\x1ftrue\n'
    case "$2" in
    screens)
        declare -A model hz showing
        while IFS=$'\t' read -r name m h active; do
            model[$name]="$m" hz[$name]="$h" showing[$name]="$active"
        done <"$SHARE_TMP/monitors.tsv"

        # <name length>:<name>:<x>:<y>:<width>:<height>;
        LC_ALL=C
        list="${XDPH_OUTPUT_SHARING_LIST:-}"
        while [[ "$list" == *';'* ]]; do
            len="${list%%:*}"
            list="${list#*:}"
            name="${list:0:len}"
            list="${list:len+1}"
            IFS=: read -r _ _ width height <<<"${list%%;*}"
            list="${list#*;}"
            row "$name: ${model[$name]:-unknown}" \
                "${width}×${height} at ${hz[$name]:-?} Hz, showing workspace ${showing[$name]:-?}" \
                "$(preview "output-$name" video-display)" "screen:$name"
        done
        ;;
    windows)
        declare -A stable where
        while IFS=$'\t' read -r address id workspace monitor size; do
            stable[$address]="$id" where[$address]="workspace $workspace on $monitor, $size"
        done <"$SHARE_TMP/windows.tsv"

        # <id>[HC>]<class>[HT>]<title>[HE>]<address>[HA>]
        list="${XDPH_WINDOW_SHARING_LIST:-}"
        while [[ "$list" == *'[HA>]'* ]]; do
            entry="${list%%'[HA>]'*}"
            list="${list#*'[HA>]'}"
            id="${entry%%'[HC>]'*}"
            entry="${entry#*'[HC>]'}"
            class="${entry%%'[HT>]'*}"
            class="${class//[[:cntrl:]]/ }"
            entry="${entry#*'[HT>]'}"
            title="${entry%%'[HE>]'*}"
            title="${title//[[:cntrl:]]/ }"
            printf -v address '0x%x' "${entry#*'[HE>]'}" 2>/dev/null
            icon="$SHARE_TMP/window-${stable[$address]:-none}.jpg"
            if [[ ! -s "$icon" ]]; then
                desktop="$(grep -lsiFx "StartupWMClass=$class" "$HOME"/.local/share/applications/*.desktop /usr/share/applications/*.desktop | head -1)"
                icon="$([[ -n "$desktop" ]] && sed -n 's/^Icon=//p' "$desktop" | head -1)"
                [[ -z "$icon" ]] && icon="${class,,}"
                icon="${icon/steam_app_/steam_icon_}"
            fi
            row "${title:-$class}" "$class, ${where[$address]:-unknown location}" "$icon" "window:$id"
        done
        ;;
    workspaces)
        declare -A monitor_of workspace_id count state classes
        while IFS=$'\t' read -r name wid monitor n s c; do
            monitor_of[$name]="$monitor" workspace_id[$name]="$wid" count[$name]="$n" state[$name]="$s" classes[$name]="$c"
        done <"$SHARE_TMP/workspaces.tsv"

        # <name length>:<name>:<id>;
        LC_ALL=C
        list="${XDPH_WORKSPACE_SHARING_LIST_V2:-}"
        while [[ "$list" == *';'* ]]; do
            len="${list%%:*}"
            list="${list#*:}"
            name="${list:0:len}"
            list="${list:len+1}"
            id="${list%%;*}"
            list="${list#*;}"
            monitor="${monitor_of[$name]:-unknown monitor}"
            windows="${count[$name]:-0}"
            status="${state[$name]:-}"
            if [[ -z "$status" ]]; then
                detail="Details unavailable"
            elif [[ "$windows" == 0 ]]; then
                detail="${status^} with no windows"
            else
                detail="${status^} with $windows window$([[ "$windows" == 1 ]] || printf s)${classes[$name]:+: ${classes[$name]}}"
            fi
            if [[ "${state[$name]:-}" == "on screen" ]]; then
                icon="$(preview "output-$monitor" user-desktop)"
            else
                icon="$(preview "workspace-${workspace_id[$name]:-none}" user-desktop)"
            fi
            row "Workspace $name on $monitor" "$detail" "$icon" "workspace-id:$id"
        done | sort -k2,2n
        ;;
    region)
        row "Select a region…" "Draw an area of the screen" edit-select-all region
        ;;
    esac
    exit 0
fi

capture() {
    local file="$SHARE_TMP/$1.jpg"
    shift
    { timeout 1 grim "$@" -s 0.1 -t jpeg -q 85 "$file.part" && mv -f "$file.part" "$file"; } &
}

compose_workspace() {
    local id="$1" width="$2" height="$3" monitor_x="$4" monitor_y="$5" window x y w h
    local args=(-size "${width}x${height}" "xc:#0E0E0E")
    while read -r window x y w h; do
        [[ -s "$SHARE_TMP/window-$window.jpg" ]] || continue
        args+=("(" "$SHARE_TMP/window-$window.jpg" -resize "${w}x${h}!" ")" -geometry "$(printf '%+d%+d' "$x" "$y")" -composite)
    done < <(jq -r --argjson id "$id" --argjson mx "$monitor_x" --argjson my "$monitor_y" \
        'map(select(.workspace.id == $id and .hidden != true and .mapped != false)) | sort_by([.floating, .fullscreen]) | .[]
         | [.stableId, (((.at[0] - $mx) / 10) | floor), (((.at[1] - $my) / 10) | floor), ((.size[0] / 10) | ceil), ((.size[1] / 10) | ceil)] | @tsv' \
        "$SHARE_TMP/clients.json")
    local file="$SHARE_TMP/workspace-$id.jpg"
    [[ ${#args[@]} -gt 2 ]] && timeout 1 magick "${args[@]}" "jpeg:$file.part" && mv -f "$file.part" "$file"
}

prepare() {
    local name id width height x y
    timeout 1 hyprctl -j monitors >"$SHARE_TMP/monitors.json"
    timeout 1 hyprctl -j clients >"$SHARE_TMP/clients.json"
    timeout 1 hyprctl -j workspaces >"$SHARE_TMP/workspaces.json"

    jq -r '.[] | [.name, "\(.make) \(.model)", (.refreshRate | round), .activeWorkspace.name] | @tsv' \
        "$SHARE_TMP/monitors.json" >"$SHARE_TMP/monitors.tsv"
    jq -r --slurpfile m "$SHARE_TMP/monitors.json" \
        '($m[0] | map({(.id | tostring): .name}) | add) as $names
         | .[] | [.address, .stableId, .workspace.name, ($names[.monitor | tostring] // "unknown monitor"), "\(.size[0])×\(.size[1])"] | @tsv' \
        "$SHARE_TMP/clients.json" >"$SHARE_TMP/windows.tsv"
    jq -r --slurpfile m "$SHARE_TMP/monitors.json" --slurpfile c "$SHARE_TMP/clients.json" \
        '($m[0] | map(.activeWorkspace.name)) as $active
         | .[] | .name as $w
         | [$w, .id, .monitor, .windows, (if ($active | index($w)) then "on screen" else "hidden" end),
            ([$c[0][] | select(.workspace.name == $w) | .class] | unique | join(", "))] | @tsv' \
        "$SHARE_TMP/workspaces.json" >"$SHARE_TMP/workspaces.tsv"

    while read -r name; do capture "output-$name" -o "$name"; done < <(jq -r '.[].name' "$SHARE_TMP/monitors.json")
    while read -r id; do capture "window-$id" -T "$id"; done < <(jq -r '.[].stableId' "$SHARE_TMP/clients.json")
    wait

    while read -r id width height x y; do
        compose_workspace "$id" "$width" "$height" "$x" "$y" &
    done < <(jq -r --slurpfile m "$SHARE_TMP/monitors.json" \
        '($m[0] | map(.activeWorkspace.id)) as $active
         | .[] | select(.id as $i | $active | index($i) | not) | .monitor as $name
         | ($m[0][] | select(.name == $name)) as $o
         | (if (($o.transform // 0) % 2) == 1 then [$o.height, $o.width] else [$o.width, $o.height] end) as $size
         | [.id, (($size[0] / $o.scale / 10) | ceil), (($size[1] / $o.scale / 10) | ceil), $o.x, $o.y] | @tsv' \
        "$SHARE_TMP/workspaces.json")
    wait
}

# if this picker can't work, sharing should still work through the stock one
use_default_picker() {
    printf 'screenshare-picker: %s, using the default picker\n' "$1" >&2
    timeout 1 notify-send -a "Screenshare picker" "Using the default picker" "$1" >/dev/null 2>&1
    [[ -n "${SHARE_TMP:-}" ]] && rm -rf -- "$SHARE_TMP"
    exec hyprland-share-picker "${original_args[@]}"
}

original_args=("$@")
flags=""
for arg in "$@"; do
    [[ "$arg" == "--allow-token" ]] && flags="r"
done

command -v rofi >/dev/null || use_default_picker "rofi is not installed"
[[ "${XDPH_OUTPUT_SHARING_LIST:-}" =~ ^([0-9]+:[^\;]+\;)+$ ]] || use_default_picker "the portal's monitor list changed format"
windows="${XDPH_WINDOW_SHARING_LIST:-}"
[[ -z "$windows" || "$windows" == *'[HC>]'*'[HT>]'*'[HE>]'*'[HA>]' ]] || use_default_picker "the portal's window list changed format"

SHARE_TMP="$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}" share-picker.XXXXXX)" || use_default_picker "could not create a temp folder"
export SHARE_TMP
trap 'rm -rf -- "$SHARE_TMP"' EXIT
trap 'exit 130' INT TERM HUP

: >"$SHARE_TMP/monitors.tsv"
: >"$SHARE_TMP/windows.tsv"
: >"$SHARE_TMP/workspaces.tsv"

# previews are optional, so a slow or hung capture can't hold the picker back
prepare >/dev/null 2>&1 &
timeout 1.5 tail -s 0.01 --pid=$! -f /dev/null

self="$(realpath "$0")"
modes="SCREENS:$self --tab screens"
[[ -n "$windows" ]] && modes+=",WINDOWS:$self --tab windows"
[[ "${XDPH_WORKSPACE_SHARING_LIST_V2:-}" =~ ^([0-9]+:.+:[0-9]+\;)+$ ]] && modes+=",WORKSPACES:$self --tab workspaces"
command -v slurp >/dev/null && modes+=",REGION:$self --tab region"

start="SCREENS"
while :; do
    : >"$SHARE_TMP/pick"
    status=0
    rofi -replace -modes "$modes" -show "$start" -theme "${self%/*}/screenshare-picker.rasi" >/dev/null 2>"$SHARE_TMP/rofi.log" || status=$?

    # rofi exits the same way for Escape and for a broken theme, only its log tells them apart
    grep -qE 'Failed to (open|parse) theme' "$SHARE_TMP/rofi.log" && use_default_picker "the rofi theme has an error"
    case "$status" in
    0 | 1 | 130 | 143) ;;
    *) use_default_picker "rofi exited with code $status" ;;
    esac

    pick="$(<"$SHARE_TMP/pick")"
    [[ -z "$pick" ]] && exit 0

    # slurp has to run after rofi closes, cancelling it goes back to the picker
    if [[ "$pick" == "region" ]]; then
        start="REGION"
        area="$(slurp -f '%o@%X,%Y,%W,%H')" || continue
        [[ "$area" =~ ^[^@]+@[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]] || continue
        pick="region:$area"
    fi

    printf '[SELECTION]%s/%s\n' "$flags" "$pick"
    exit 0
done
