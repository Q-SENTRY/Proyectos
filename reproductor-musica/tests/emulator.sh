#!/bin/bash
# Prueba en emulador: instala, añade música al "teléfono", abre la app, reproduce y pasa a segundo plano.
set -x
OUT=test-results; rm -rf $OUT; mkdir -p $OUT
PKG=com.qsentry.reproductor
shot(){ adb exec-out screencap -p > "$OUT/$1.png"; }
adb wait-for-device; sleep 5
adb install -r reproductor-musica/android/app/build/outputs/apk/debug/app-debug.apk
python3 reproductor-musica/tests/make_audio.py /tmp/musica
adb shell mkdir -p /sdcard/Music
for f in /tmp/musica/*.wav; do adb push "$f" /sdcard/Music/; done
adb shell content call --uri content://media --method scan_volume --arg external_primary
sleep 8
adb shell content query --uri content://media/external/audio/media --projection title:artist:is_music > $OUT/mediastore.txt
adb shell pm grant $PKG android.permission.READ_MEDIA_AUDIO
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS
adb logcat -c
adb shell am start -W -n $PKG/.MainActivity
sleep 20
adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" > $OUT/foreground.txt
shot 1-biblioteca
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml $OUT/ui.xml
read W H < <(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1 | tr x ' ')
echo "Pantalla: ${W}x${H}"
# Primera canción de la lista (coordenadas relativas medidas en la captura)
adb shell input tap $(( W * 40 / 100 )) $(( H * 829 / 1000 ))
sleep 5
shot 2-reproduciendo-mini
adb shell input tap $(( W * 40 / 100 )) $(( H * 950 / 1000 ))
sleep 3
shot 3-reproductor
adb shell input keyevent KEYCODE_HOME
sleep 15
adb shell dumpsys media_session > $OUT/media_session.txt
adb shell dumpsys activity services $PKG > $OUT/servicios.txt
adb shell cmd statusbar expand-notifications; sleep 3
shot 4-segundo-plano-notificacion
adb shell input keyevent KEYCODE_SLEEP; sleep 3; adb shell input keyevent KEYCODE_WAKEUP; sleep 3
shot 5-pantalla-bloqueada
adb logcat -d > $OUT/logcat-completo.txt
grep -E "REP|Capacitor/Console|FATAL|ActivityManager.*qsentry|ActivityTaskManager.*qsentry|MediaSession" $OUT/logcat-completo.txt > $OUT/logcat.txt
{
  echo "== Resultado =="
  grep -q "REP scan .* canciones" $OUT/logcat.txt && echo "OK detecta música: $(grep -o 'REP scan [0-9]* canciones' $OUT/logcat.txt | tail -1)" || echo "FALLO detección"
  grep -q "REP play" $OUT/logcat.txt && echo "OK reproduce: $(grep -o 'REP play.*' $OUT/logcat.txt | head -1)" || echo "FALLO reproducción"
  grep -q "REP audio-error" $OUT/logcat.txt && echo "FALLO error de audio: $(grep -o 'REP audio-error.*' $OUT/logcat.txt | head -1)"
  grep -q "state=PlaybackState {state=3" $OUT/media_session.txt && echo "OK sigue sonando en segundo plano (state=PLAYING)" || echo "REVISAR estado en segundo plano"
  grep -q "MediaSessionService" $OUT/servicios.txt && echo "OK servicio en primer plano activo" || echo "REVISAR servicio"
  grep -q "FATAL EXCEPTION" $OUT/logcat-completo.txt && echo "FALLO crash detectado" || echo "OK sin crashes"
} | tee $OUT/RESUMEN.txt
rm -f $OUT/logcat-completo.txt
exit 0
