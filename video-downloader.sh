#!/usr/bin/env bash

INPUT_THEME="$HOME/.config/rofi/ytdlp-input.rasi"
CONFIRM_THEME="$HOME/.config/rofi/ytdlp-confirm.rasi"
TERMINAL="kitty"
DLDIR="$HOME/Downloads"

clip=$(wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null)
if [[ "$clip" =~ ^https?://[^[:space:]]+$ ]]; then
    prefill="$clip"
else
    prefill=""
fi

url=$(rofi -dmenu -p "URL" -filter "$prefill" -theme "$INPUT_THEME")
[ -z "$url" ] && exit 0

if [[ ! "$url" =~ ^https?://[^[:space:]]+$ ]]; then
    notify-send "yt-dlp" "Not a valid URL:"$'\n'"$url"
    exit 1
fi

notify-send -t 3000 "yt-dlp" "Fetching info…"
title=$(yt-dlp --no-warnings --print "%(title)s" "$url" 2>/dev/null | head -1)
thumb=$(yt-dlp --no-warnings --print "%(thumbnail)s" "$url" 2>/dev/null | head -1)

if [ -z "$title" ]; then
    notify-send "yt-dlp" "Couldn't fetch info — bad URL or login needed?"
    exit 1
fi

thumb_file=$(mktemp /tmp/ytdlp_thumb.XXXXXX.jpg)
[ -n "$thumb" ] && curl -sL "$thumb" -o "$thumb_file"

pick=$(printf "Best available\n2160p (4K)\n1440p\n1080p\n720p\n480p\n360p\nAudio only\nCancel" |
    rofi -dmenu \
        -mesg "<b>$title</b>" \
        -theme "$CONFIRM_THEME" \
        -theme-str "imagebox { background-image: url(\"$thumb_file\", height); }
                       window { height: 440px; }
                       listview { lines: 9; }")

rm -f "$thumb_file"
[ -z "$pick" ] && exit 0

case "$pick" in
Cancel*) exit 0 ;;
"Best available") fmt="bestvideo+bestaudio/best" ;;
"Audio only") fmt="bestaudio" ;;
*)
    height=$(printf "%s" "$pick" | grep -oE '^[0-9]+')
    fmt="bv*[height<=${height}]+ba/b[height<=${height}]"
    ;;
esac

"$TERMINAL" --class ytdlp-float -e bash -c "
    echo 'Downloading: $title'
    echo 'Quality: $pick'
    echo
    yt-dlp --cookies-from-browser firefox \
        -f '$fmt' --merge-output-format mp4 \
        -P '$DLDIR' '$url'
    status=\$?
    echo
    if [ \$status -eq 0 ]; then
        echo '✓ Done'
        notify-send 'yt-dlp' 'Done ✓\n$title'
    else
        echo '✗ Failed — cleaning partial files'
        find '$DLDIR' -maxdepth 1 \( -name '*.part' -o -name '*.ytdl' \) -delete 2>/dev/null
        notify-send 'yt-dlp' 'Failed ✗\n$title'
    fi
    echo
    echo 'Press enter to close…'; read
"
