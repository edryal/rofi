#!/usr/bin/env bash
set -uo pipefail

THEME_DIR="$HOME/.config/rofi"
MENU_THEME="$THEME_DIR/powermenu.rasi"
CONFIRM_THEME="$THEME_DIR/confirm.rasi"

# uptime string for the message line
uptime="$(uptime -p 2>/dev/null | sed -e 's/up //g')"
[[ -z "$uptime" ]] && uptime="unknown"

shutdown='󰐥'
reboot='󰑙'
lock='󰌾'
logout='󰍃'
yes='󰄬'
no='󰅖'

menu_cmd() {
    rofi -dmenu -i \
        -p "Power" \
        -mesg "Uptime: $uptime" \
        -theme "$MENU_THEME"
}

confirm_cmd() {
    rofi -dmenu -i \
        -p "Confirm" \
        -mesg "Are you sure?" \
        -theme "$CONFIRM_THEME"
}

confirm() {
    local choice
    choice="$(printf '%s\n%s\n' "$yes" "$no" | confirm_cmd)"
    [[ "$choice" == "$yes" ]]
}

chosen="$(printf '%s\n%s\n%s\n%s\n' \
    "$shutdown" "$reboot" "$logout" "$lock" | menu_cmd)"

[[ -z "$chosen" ]] && exit 0

case "$chosen" in
"$lock")
    loginctl lock-session
    ;;
"$logout")
    if confirm; then
        if command -v hyprctl >/dev/null 2>&1; then
            hyprctl dispatch exit
        else
            loginctl terminate-user "$USER"
        fi
    fi
    ;;
"$reboot")
    confirm && systemctl reboot
    ;;
"$shutdown")
    confirm && systemctl poweroff
    ;;
esac
