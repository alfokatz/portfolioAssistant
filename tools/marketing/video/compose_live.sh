#!/usr/bin/env bash
# Arma el video live action "Porty en tu día" (24 s, 1080x1920, 30 fps):
# planos de contexto generados con IA (Sunra, Seedance 2.0) intercalados con
# los planos de producto del motion design (UI real de la app), más la
# locución con IA (ElevenLabs vía Sunra).
#
# Uso: tools/marketing/video/compose_live.sh <dir_clips> <motion.mp4> <salida.mp4>
# <dir_clips> tiene L1_cocina.mp4, L2_colectivo.mp4, L4_sillon.mp4,
# L5_pulgar.mp4, vo1..vo6.mp3 y los overlays de render_overlays.mjs.
set -euo pipefail
C="$1"; MD="$2"; OUT="$3"
W=1080; H=1920; FPS=30

# Plano live: recorte del clip, push-in lento (4 % en toda la toma), leve
# calidez de color.
live() { # in from dur
  echo "[$1:v]trim=start=$2:duration=$3,setpts=PTS-STARTPTS,fps=$FPS,scale=$W:$H:flags=lanczos,scale=w='$W*(1+0.04*t/$3)':h=-2:eval=frame:flags=bicubic,crop=$W:$H,eq=saturation=1.04:gamma=1.02,setsar=1"
}
md() { # from dur
  echo "[0:v]trim=start=$1:duration=$2,setpts=PTS-STARTPTS,fps=$FPS,scale=$W:$H,setsar=1"
}

ffmpeg -y -loglevel error \
  -i "$MD" \
  -i "$C/L1_cocina.mp4" -i "$C/L2_colectivo.mp4" -i "$C/L4_sillon.mp4" -i "$C/L5_pulgar.mp4" \
  -loop 1 -t 3.2 -i "$C/ov_plata.png" -loop 1 -t 2.6 -i "$C/ov_juntala.png" \
  -i "$C/vo1.mp3" -i "$C/vo2.mp3" -i "$C/vo3.mp3" -i "$C/vo4.mp3" -i "$C/vo5.mp3" -i "$C/vo6.mp3" \
  -filter_complex "
$(live 1 0.2 3.2)[a0];
[5:v]format=rgba,fade=in:st=0.25:d=0.45:alpha=1,setpts=PTS-STARTPTS[o1];
[a0][o1]overlay=0:0:shortest=1[A];
$(live 2 1.0 2.6)[b0];
[6:v]format=rgba,fade=in:st=0.1:d=0.4:alpha=1,setpts=PTS-STARTPTS[o2];
[b0][o2]overlay=0:0:shortest=1[B];
$(md 5.2 3.8)[Cc];
$(live 3 1.0 3.0)[D];
$(md 10.3 3.0)[E];
$(live 4 2.3 2.0)[F];
$(md 15.0 3.2)[G];
$(md 18.8 3.2)[Hh];
[A][B][Cc][D][E][F][G][Hh]concat=n=8:v=1:a=0,format=yuv420p[v];
[7:a]adelay=400|400[v1];[8:a]adelay=3600|3600[v2];[9:a]adelay=6200|6200[v3];
[10:a]adelay=9900|9900[v4];[11:a]adelay=15800|15800[v5];[12:a]adelay=21300|21300[v6];
[v1][v2][v3][v4][v5][v6]amix=inputs=6:normalize=0,apad,atrim=0:24,loudnorm=I=-16:TP=-1.5:LRA=11[a]
" -map "[v]" -map "[a]" -t 24 \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r $FPS \
  -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$OUT"
echo "$OUT"
