#!/usr/bin/env bash
# Runs scrcpy to play with a physical controller recognized by Android as HID.
#
# Usage:
#   ./run.sh          # recommended profile: 60 FPS
#   ./run.sh 30       # prioritizes low power consumption
#   ./run.sh 60       # balanced profile (recommended for this machine)
#   ./run.sh 90       # not recommended: places significantly higher load on phone and PC
#   ./run.sh 120      # not recommended: likely to cause stuttering
#
# You can pass additional scrcpy options after the FPS argument:
#   ./run.sh 60 --fullscreen

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CONTROLLER_MAPPING_FILE="$SCRIPT_DIR/controller-mapping.json"
readonly CONTROLLER_PRELOAD_SOURCE="$SCRIPT_DIR/controller-mapping-preload.c"
readonly CONTROLLER_PRELOAD_LIBRARY="$SCRIPT_DIR/.controller-mapping-preload.so"
readonly DEFAULT_FPS=60
# Phone resolution is 720x1600: 1920 did not downscale it. 1024 noticeably lowers
# capture/decoding overhead and was the most stable profile on this PC.
readonly MAX_SIZE=1024
readonly VIDEO_BIT_RATE=6M
readonly AUDIO_BIT_RATE=128K

usage() {
  sed -n '2,14p' "$0"
}

die() {
  printf '\033[1;31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

if [[ ${1:-} == '-h' || ${1:-} == '--help' ]]; then
  usage
  exit 0
fi

fps="$DEFAULT_FPS"
if [[ ${1:-} =~ ^[0-9]+$ ]]; then
  fps="$1"
  shift
fi

(( fps >= 1 && fps <= 240 )) || die "FPS must be between 1 and 240."

command -v scrcpy >/dev/null 2>&1 || die "scrcpy not found. Run ./installing.sh first."

# On this system, SDL over XWayland presents frames more consistently than
# its native Wayland backend. It can be overridden, for example:
# SDL_VIDEODRIVER=wayland ./run.sh
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"

if [[ -f $CONTROLLER_MAPPING_FILE ]]; then
  command -v jq >/dev/null 2>&1 || die "jq missing to read controller-mapping.json. Run ./installing.sh first."
  map_a="$(jq -r '.buttons.A // empty' "$CONTROLLER_MAPPING_FILE")" \
    || die "controller-mapping.json does not contain valid JSON."
  map_b="$(jq -r '.buttons.B // empty' "$CONTROLLER_MAPPING_FILE")"
  map_x="$(jq -r '.buttons.X // empty' "$CONTROLLER_MAPPING_FILE")"
  map_y="$(jq -r '.buttons.Y // empty' "$CONTROLLER_MAPPING_FILE")"

  button_index() {
    case "$1" in
      A) printf 'b0' ;;
      B) printf 'b1' ;;
      X) printf 'b2' ;;
      Y) printf 'b3' ;;
      *) die "Invalid button in controller-mapping.json: '$1'. Use A, B, X, or Y." ;;
    esac
  }

  map_a="$(button_index "$map_a")"
  map_b="$(button_index "$map_b")"
  map_x="$(button_index "$map_x")"
  map_y="$(button_index "$map_y")"

  # scrcpy starts SDL without explicitly initializing the gamepad subsystem,
  # so the SDL configuration file is ignored. We generate the
  # SDL mapping line from JSON and the local adapter adds it when SDL initializes.
  sdl_mapping="$(jq -r \
    --arg a "$map_a" --arg b "$map_b" --arg x "$map_x" --arg y "$map_y" \
    '.sdl_guid + ",Xbox Series X Controller (custom),a:" + $a + ",b:" + $b + ",x:" + $x + ",y:" + $y + ",back:b6,guide:b8,start:b7,leftstick:b9,rightstick:b10,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,misc1:b11,leftx:a0,lefty:a1,rightx:a3,righty:a4,lefttrigger:a2,righttrigger:a5,platform:Linux"' \
    "$CONTROLLER_MAPPING_FILE")"

  command -v cc >/dev/null 2>&1 || die "gcc missing to build controller adapter. Run ./installing.sh first."
  if [[ ! -f $CONTROLLER_PRELOAD_LIBRARY || $CONTROLLER_PRELOAD_SOURCE -nt $CONTROLLER_PRELOAD_LIBRARY ]]; then
    cc -shared -fPIC -O2 -o "$CONTROLLER_PRELOAD_LIBRARY" \
      "$CONTROLLER_PRELOAD_SOURCE" -lSDL3 -ldl \
      || die "Failed to compile controller adapter."
  fi

  export SCRCPY_CONTROLLER_MAPPING="$sdl_mapping"
  export LD_PRELOAD="$CONTROLLER_PRELOAD_LIBRARY${LD_PRELOAD:+:$LD_PRELOAD}"
  printf '\033[1;34m==>\033[0m Native remapping loaded from %s\n' "$(basename "$CONTROLLER_MAPPING_FILE")"
fi

printf '\033[1;34m==>\033[0m Video: %s px max, %s, SDL backend %s\n' \
  "$MAX_SIZE" "$VIDEO_BIT_RATE" "$SDL_VIDEODRIVER"

# H.264 is the lightest and most compatible option for Intel HD 530.
# --capture-orientation is not set: scrcpy can automatically rotate between portrait and
# landscape when Android rotates the screen. A 0 ms buffer avoids added latency.
scrcpy \
  --max-fps="$fps" \
  --max-size="$MAX_SIZE" \
  --video-codec=h264 \
  --video-bit-rate="$VIDEO_BIT_RATE" \
  --audio-bit-rate="$AUDIO_BIT_RATE" \
  --video-buffer=0 \
  --gamepad=uhid \
  --stay-awake \
  "$@"
