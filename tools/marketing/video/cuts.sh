#!/usr/bin/env bash
# Cortes de 15–20 s por función, desde el video completo "Porty te acompaña"
# (compose_live.sh). Cada corte: Porty sale de la pantalla → escenas → demo
# de la función → cierre "Descargala gratis".
#
# Uso: tools/marketing/video/cuts.sh <PR1_live_action_porty.mp4> <salida_dir>
#
# Segmentos del video completo (segundos):
#   S0 0–4 Porty sale de la pantalla · A 4–7 cocina · B 7–9,6 colectivo
#   C 9,6–13,4 cards de cartera · D 13,4–16,4 sillón (NVDA +6 %)
#   W 16,4–21,4 informe semanal · F 21,4–23,4 pulgar ("Preguntame…")
#   X 23,4–27,9 comparar · Y 27,9–32,4 diversificar · Z 32,4–37,2 metas
#   H 37,2–40,4 cierre
set -euo pipefail
SRC="$1"; OUT="$2"; mkdir -p "$OUT"

declare -A SEG=(
  [S0]="0 4" [A]="4 7" [B]="7 9.6" [C]="9.6 13.4" [D]="13.4 16.4" [W]="16.4 21.4"
  [F]="21.4 23.4" [X]="23.4 27.9" [Y]="27.9 32.4" [Z]="32.4 37.2" [H]="37.2 40.4"
)

cut() { # nombre segmentos...
  local name="$1"; shift
  local filters="" labels="" i=0
  for s in "$@"; do
    read -r a b <<< "${SEG[$s]}"
    filters+="[0:v]trim=start=$a:end=$b,setpts=PTS-STARTPTS[v$i];"
    labels+="[v$i]"; i=$((i+1))
  done
  ffmpeg -y -loglevel error -i "$SRC" -f lavfi -i anullsrc=r=48000:cl=stereo \
    -filter_complex "${filters}${labels}concat=n=$i:v=1:a=0,format=yuv420p[v]" \
    -map "[v]" -map 1:a -shortest -c:v libx264 -preset slow -crf 18 -r 30 \
    -c:a aac -b:a 128k -movflags +faststart "$OUT/$name.mp4"
  printf '%s %ss\n' "$OUT/$name.mp4" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$name.mp4")"
}

cut corte_informe_semanal   S0 A D W H
cut corte_comparar_sp500    S0 C F X H
cut corte_diversificar      S0 C F Y H
cut corte_metas_ahorro      S0 A F Z H
