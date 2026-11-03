#!/usr/bin/env bash
# Arma el video PR1 "Esto es Porty" (20 s, 1080x1920, 30 fps) con las escenas
# que genera tools/marketing/render_social.mjs. Zoom lento por escena y
# fundidos de 0,4 s. Pista de audio muda: la música se elige al publicar,
# desde la biblioteca comercial de Instagram/TikTok.
# Uso: tools/marketing/render_pr1.sh <carpeta_piezas>
set -euo pipefail
dir="$1"
fps=30
fade=0.4
scenes=(PR1_s1_hook PR1_s2_esto_es_porty PR1_s3_para_quien PR1_s4_te_explica PR1_s5_cierre)
# Duración visible de cada escena (2/4/5/5/4 s = 20 s); las primeras cuatro
# suman el fundido para que el total quede en 20 s. La última (con el pie
# B + C + D) dura 4 s: el disclaimer queda en pantalla más de 3 s.
durs=(2.4 4.4 5.4 5.4 4.0)

inputs=()
filters=""
for i in "${!scenes[@]}"; do
  frames=$(python3 -c "print(round(${durs[$i]}*$fps))")
  inputs+=(-i "$dir/${scenes[$i]}.png")
  filters+="[$i:v]scale=1080:1920,zoompan=z='min(zoom+0.0005,1.035)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$frames:s=1080x1920:fps=$fps,format=yuv420p,setsar=1[v$i];"
done

# Encadena los fundidos: offset = suma de duraciones previas - fundidos previos.
prev="v0"
offset=0
for i in 1 2 3 4; do
  offset=$(python3 -c "print(round($offset + ${durs[$((i-1))]} - $fade, 3))")
  filters+="[$prev][v$i]xfade=transition=fade:duration=$fade:offset=$offset[x$i];"
  prev="x$i"
done
filters="${filters%;}"

ffmpeg -y -loglevel error "${inputs[@]}" -f lavfi -i anullsrc=r=44100:cl=stereo \
  -filter_complex "$filters" -map "[$prev]" -map 5:a -shortest \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -r $fps \
  -c:a aac -b:a 128k -movflags +faststart "$dir/PR1_esto_es_porty.mp4"
echo "$dir/PR1_esto_es_porty.mp4"
