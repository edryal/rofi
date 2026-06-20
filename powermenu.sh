#!/usr/bin/env bash
# =============================================================================
#  powermenu.sh  —  rofi power menu
#
#  Originally adi1090x's type-4 power menu, reworked to use the custom
#  rosy-pink rofi themes (powermenu.rasi + confirm.rasi) and tidied up.
#
#  Actions: shutdown · reboot · logout · lock
#  Destructive actions (shutdown/reboot/logout) ask for confirmation.
#
#  Install: put this + powermenu.rasi + confirm.rasi + shared-colors.rasi in
#  ~/.config/rofi/  and bind it in Hyprland, e.g.:
#      bind = $mod, Escape, exec, ~/.config/rofi/powermenu.sh
# =============================================================================
set -uo pipefail

THEME_DIR="$HOME/.config/rofi"
MENU_THEME="$THEME_DIR/powermenu.rasi"
CONFIRM_THEME="$THEME_DIR/confirm.rasi"

# uptime string for the message line
uptime="$(uptime -p 2>/dev/null | sed -e 's/up //g')"
[[ -z "$uptime" ]] && uptime="unknown"

# option glyphs (Nerd Font)
shutdown='󰐥'
reboot='󰑙'
lock='󰌾'
logout='󰍃'
yes='󰄬'
no='󰅖'

# ---- rofi launchers ----
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

# ask yes/no; returns 0 if confirmed
confirm() {
    local choice
    choice="$(printf '%s\n%s\n' "$yes" "$no" | confirm_cmd)"
    [[ "$choice" == "$yes" ]]
}

# ---- show the menu (order: shutdown, reboot, logout, lock) ----
chosen="$(printf '%s\n%s\n%s\n%s\n' \
    "$shutdown" "$reboot" "$logout" "$lock" | menu_cmd)"

[[ -z "$chosen" ]] && exit 0

case "$chosen" in
"$lock")
    loginctl lock-session
    ;;
"$logout")
    if confirm; then
        # Hyprland; swap for your compositor if different
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
