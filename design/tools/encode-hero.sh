#!/usr/bin/env bash
# Turns the generated hero clip into the web-ready assets used by design/index.html.
#
#   1. Makes the clip loop without a visible jump: the last FADE_FRAMES frames are
#      cross-faded into the first ones, so frame N-F is followed by frame N-F+1 again.
#   2. Grades the green glow from the clip's lime (hue ~97 deg) to the app's green
#      (#30D158, hue ~135 deg) so video and UI use one accent colour.
#   3. Exports an H.264 MP4 (no audio, fast-start) and a poster JPEG.
#
# Usage:  design/tools/encode-hero.sh path/to/original.mp4 [out_dir]
# Needs:  ffmpeg + ffprobe (libx264).
# Tuning (env vars): FADE_FRAMES (24 = 1 s at 24 fps), GRADE (ffmpeg filter, "" = none), CRF (21), POSTER_AT (seconds into the loop)
set -euo pipefail

IN=${1:?usage: encode-hero.sh input.mp4 [out_dir]}
OUT=${2:-"$(cd "$(dirname "$0")/.." && pwd)/assets"}
FADE_FRAMES=${FADE_FRAMES:-24}
GRADE=${GRADE-"hue=h=36:s=1.45,eq=contrast=1.04:brightness=-0.015"}
CRF=${CRF:-21}
POSTER_AT=${POSTER_AT:-11.5}

mkdir -p "$OUT"

FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$IN" | awk -F/ '{printf "%g", $1/($2 ? $2 : 1)}')
FRAMES=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$IN")
HEAD=$((FRAMES - FADE_FRAMES))
FADE_SECONDS=$(awk -v f="$FADE_FRAMES" -v r="$FPS" 'BEGIN { printf "%.4f", f / r }')

if [ "$HEAD" -le "$FADE_FRAMES" ]; then
  echo "clip too short ($FRAMES frames) for a $FADE_FRAMES-frame cross-fade" >&2
  exit 1
fi

# [tail] fades into [head]; the result is FRAMES-FADE_FRAMES long and ends one frame before its own start.
FILTER="[0:v]fps=${FPS},format=yuv420p,split[a][b];"
FILTER+="[a]trim=start_frame=0:end_frame=${HEAD},setpts=PTS-STARTPTS[head];"
FILTER+="[b]trim=start_frame=${HEAD}:end_frame=${FRAMES},setpts=PTS-STARTPTS[tail];"
FILTER+="[tail][head]xfade=transition=fade:duration=${FADE_SECONDS}:offset=0[loop]"
if [ -n "$GRADE" ]; then
  FILTER+=";[loop]${GRADE}[v]"
else
  FILTER+=";[loop]null[v]"
fi

# aq-mode=3 spends bits on dark areas, which is where banding shows in this clip.
ffmpeg -v error -y -i "$IN" -filter_complex "$FILTER" -map "[v]" -an \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -preset slow -crf "$CRF" \
  -x264-params aq-mode=3:aq-strength=1.1 -movflags +faststart "$OUT/hero.mp4"

ffmpeg -v error -y -ss "$POSTER_AT" -i "$OUT/hero.mp4" -frames:v 1 -q:v 3 "$OUT/hero-poster.jpg"

ls -l "$OUT/hero.mp4" "$OUT/hero-poster.jpg"
