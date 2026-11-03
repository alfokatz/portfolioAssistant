#!/usr/bin/env bash
# Arma el video live action "Porty te acompaña" (40 s, 1080x1920, 30 fps):
# planos de contexto generados con IA (Sunra, Seedance 2.0) intercalados con
# los planos de producto del motion design (UI real de la app). Sin locución
# (la voz con IA se descartó): pista muda para sumar la música al publicar.
#
# Uso: tools/marketing/video/compose_live.sh <dir_clips> <motion.mp4> <demos.mp4> <salida.mp4>
# <motion.mp4>: render de porty_ad.html; <demos.mp4>: render de porty_demos.html.
# <dir_clips> tiene L1_cocina.mp4, L2_colectivo.mp4, L4_sillon.mp4,
# L5_pulgar.mp4 y los porty_*.mov de render_companion.mjs (Porty personaje).
set -euo pipefail
C="$1"; MD="$2"; DEMOS="$3"; OUT="$4"; T=40.4
W=1080; H=1920; FPS=30

# Plano live: recorte del clip, push-in lento (4 % en toda la toma), leve
# calidez de color.
# Porty se superpone ANTES del push-in, así se mueve con la escena (queda
# "apoyado" en la superficie de la toma).
live() { # in from dur overlay_in label
  echo "[$1:v]trim=start=$2:duration=$3,setpts=PTS-STARTPTS,fps=$FPS,scale=$W:$H:flags=lanczos,eq=saturation=1.04:gamma=1.02,setsar=1[l$1];[l$1][$4:v]overlay=0:0:shortest=1,scale=w='$W*(1+0.04*t/$3)':h=-2:eval=frame:flags=bicubic,crop=$W:$H,setsar=1[$5]"
}
md() { # from dur [input]
  echo "[${3:-0}:v]trim=start=$1:duration=$2,setpts=PTS-STARTPTS,fps=$FPS,scale=$W:$H,setsar=1"
}

ffmpeg -y -loglevel error \
  -i "$MD" \
  -i "$C/L1_cocina.mp4" -i "$C/L2_colectivo.mp4" -i "$C/L4_sillon.mp4" -i "$C/L5_pulgar.mp4" \
  -i "$C/porty_cocina.mov" -i "$C/porty_colectivo.mov" -i "$C/porty_sillon.mov" -i "$C/porty_pulgar.mov" \
  -f lavfi -t $T -i anullsrc=r=48000:cl=stereo -i "$DEMOS" \
  -filter_complex "
$(md 0 4.0 10)[S0];
$(live 1 0.2 3.0 5 A);
$(live 2 1.0 2.6 6 B);
$(md 5.2 3.8)[Cc];
$(live 3 1.0 3.0 7 D);
$(md 4.2 5.0 10)[W];
$(live 4 2.3 2.0 8 F);
$(md 9.2 4.5 10)[X];
$(md 13.7 4.5 10)[Y];
$(md 18.2 4.8 10)[Z];
$(md 18.8 3.2)[Hh];
[S0][A][B][Cc][D][W][F][X][Y][Z][Hh]concat=n=11:v=1:a=0,format=yuv420p[v];
" -map "[v]" -map 9:a -t $T \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r $FPS \
  -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$OUT"
echo "$OUT"
