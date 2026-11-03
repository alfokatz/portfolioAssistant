#!/usr/bin/env bash
# Arma el video live action "Porty en tu día" (24 s, 1080x1920, 30 fps):
# planos de contexto generados con IA (Sunra, Seedance 2.0) intercalados con
# los planos de producto del motion design (UI real de la app). Sin locución
# (la voz con IA se descartó): pista muda para sumar la música al publicar.
#
# Uso: tools/marketing/video/compose_live.sh <dir_clips> <motion.mp4> <salida.mp4>
# <dir_clips> tiene L1_cocina.mp4, L2_colectivo.mp4, L4_sillon.mp4,
# L5_pulgar.mp4 y los porty_*.mov de render_companion.mjs (Porty personaje).
set -euo pipefail
C="$1"; MD="$2"; OUT="$3"
W=1080; H=1920; FPS=30

# Plano live: recorte del clip, push-in lento (4 % en toda la toma), leve
# calidez de color.
# Porty se superpone ANTES del push-in, así se mueve con la escena (queda
# "apoyado" en la superficie de la toma).
live() { # in from dur overlay_in label
  echo "[$1:v]trim=start=$2:duration=$3,setpts=PTS-STARTPTS,fps=$FPS,scale=$W:$H:flags=lanczos,eq=saturation=1.04:gamma=1.02,setsar=1[l$1];[l$1][$4:v]overlay=0:0:shortest=1,scale=w='$W*(1+0.04*t/$3)':h=-2:eval=frame:flags=bicubic,crop=$W:$H,setsar=1[$5]"
}
md() { # from dur
  echo "[0:v]trim=start=$1:duration=$2,setpts=PTS-STARTPTS,fps=$FPS,scale=$W:$H,setsar=1"
}

ffmpeg -y -loglevel error \
  -i "$MD" \
  -i "$C/L1_cocina.mp4" -i "$C/L2_colectivo.mp4" -i "$C/L4_sillon.mp4" -i "$C/L5_pulgar.mp4" \
  -i "$C/porty_cocina.mov" -i "$C/porty_colectivo.mov" -i "$C/porty_sillon.mov" -i "$C/porty_pulgar.mov" \
  -f lavfi -t 24 -i anullsrc=r=48000:cl=stereo \
  -filter_complex "
$(live 1 0.2 3.2 5 A);
$(live 2 1.0 2.6 6 B);
$(md 5.2 3.8)[Cc];
$(live 3 1.0 3.0 7 D);
$(md 10.3 3.0)[E];
$(live 4 2.3 2.0 8 F);
$(md 15.0 3.2)[G];
$(md 18.8 3.2)[Hh];
[A][B][Cc][D][E][F][G][Hh]concat=n=8:v=1:a=0,format=yuv420p[v];
" -map "[v]" -map 9:a -t 24 \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r $FPS \
  -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$OUT"
echo "$OUT"
