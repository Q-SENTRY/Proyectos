#!/bin/bash
# Prueba en emulador: instala, añade música al "teléfono", abre la app, reproduce y pasa a segundo plano.
set -x
OUT=test-results; rm -rf $OUT; mkdir -p $OUT
PKG=com.qsentry.reproductor
shot(){ adb exec-out screencap -p > "$OUT/$1.png"; }
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 3; done
sleep 60  # dejar que los servicios de Google terminen de arrancar
front(){ adb shell dumpsys activity activities | grep -q "topResumedActivity.*$PKG" || { echo 'Relanzando app'; adb shell am start -W -n $PKG/.MainActivity; sleep 12; }; }
adb install -r reproductor-musica/android/app/build/outputs/apk/final/app.apk
python3 reproductor-musica/tests/make_audio.py /tmp/musica
adb shell mkdir -p /sdcard/Music
for f in /tmp/musica/*.wav; do adb push "$f" /sdcard/Music/; done
# Audios de WhatsApp y un sonido de 0:00
python3 reproductor-musica/tests/make_audio.py /tmp/extra extra
WA="/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio"
adb shell mkdir -p "\"$WA\""
adb push /tmp/extra/AUD-20250101-WA0001.wav "$WA/"
adb push /tmp/extra/beep.wav /sdcard/Music/
adb shell content call --uri content://media --method scan_volume --arg external_primary
sleep 8
adb shell content query --uri content://media/external/audio/media --projection title:artist:is_music > $OUT/mediastore.txt
adb shell pm grant $PKG android.permission.READ_MEDIA_AUDIO
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS
adb logcat -c
adb shell am start -n $PKG/.MainActivity
sleep 1.2
shot 0-pantalla-de-carga
sleep 20
adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" > $OUT/foreground.txt
shot 1-biblioteca
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml $OUT/ui.xml
front
node reproductor-musica/tests/android-e2e.js play
adb shell input keyevent KEYCODE_HOME
sleep 15
node reproductor-musica/tests/android-e2e.js bg
adb shell dumpsys media_session > $OUT/media_session.txt
# Auriculares: doble toque = siguiente
adb logcat -d | grep -c "REP accion siguiente" > /tmp/n0
adb shell input keyevent KEYCODE_HEADSETHOOK KEYCODE_HEADSETHOOK
sleep 4
adb logcat -d | grep -c "REP accion siguiente" > /tmp/n1
# Triple toque = anterior
adb shell input keyevent KEYCODE_HEADSETHOOK KEYCODE_HEADSETHOOK KEYCODE_HEADSETHOOK
sleep 4
adb shell dumpsys appwidget > $OUT/widgets.txt
# Prueba de extremo a extremo: carpeta WhatsApp y borrado real
adb shell am start -W -n $PKG/.MainActivity; sleep 5
node reproductor-musica/tests/android-e2e.js
sleep 2
adb shell content query --uri content://media/external/audio/media --projection title > $OUT/mediastore-final.txt

adb shell dumpsys activity services $PKG > $OUT/servicios.txt
adb shell cmd statusbar expand-notifications; sleep 3
shot 4-segundo-plano-notificacion
adb shell cmd statusbar collapse
adb shell locksettings set-pin 1234
adb shell input keyevent KEYCODE_SLEEP; sleep 3; adb shell input keyevent KEYCODE_WAKEUP; sleep 3
shot 5-pantalla-bloqueada
adb shell dumpsys window | grep -i "mDreamingLockscreen\|isKeyguardShowing\|mShowingLockscreen" > $OUT/bloqueo.txt
adb shell input text 1234; adb shell input keyevent KEYCODE_ENTER; sleep 2
adb shell locksettings clear --old 1234
adb shell input keyevent KEYCODE_HOME; sleep 2
adb shell input swipe 160 560 160 120 300; sleep 2
shot 11-cajon-de-apps
adb logcat -d > $OUT/logcat-completo.txt
grep -E "REP|Capacitor/Console|FATAL|ActivityManager.*qsentry|ActivityTaskManager.*qsentry|MediaSession" $OUT/logcat-completo.txt > $OUT/logcat.txt
{
  echo "== Resultado =="
  grep -q "REP scan .* canciones" $OUT/logcat.txt && echo "OK detecta música: $(grep -o 'REP scan [0-9]* canciones' $OUT/logcat.txt | tail -1)" || echo "FALLO detección"
  grep -q "REP play" $OUT/logcat.txt && echo "OK reproduce: $(grep -o 'REP play.*' $OUT/logcat.txt | head -1)" || echo "FALLO reproducción"
  grep -q "REP audio-error" $OUT/logcat.txt && echo "FALLO error de audio: $(grep -o 'REP audio-error.*' $OUT/logcat.txt | head -1)"
  grep -q "state=PlaybackState {state=3" $OUT/media_session.txt && echo "OK sigue sonando en segundo plano (state=PLAYING)" || echo "REVISAR estado en segundo plano"
  grep -q "MediaSessionService" $OUT/servicios.txt && echo "OK servicio en primer plano activo" || echo "REVISAR servicio"
 [ "$(cat /tmp/n1)" -gt "$(cat /tmp/n0)" ] && echo "OK auriculares doble toque = siguiente" || echo "FALLO doble toque"
  grep -q "REP headset triple" $OUT/logcat.txt && echo "OK auriculares triple toque = anterior" || echo "REVISAR triple toque"
  grep -q "REP crossfade" $OUT/logcat.txt && echo "OK transición suave entre canciones" || echo "FALLO transición"
  grep -q "REP viz-error" $OUT/logcat.txt && echo "FALLO visualizador" || echo "OK visualizador sin errores"
  grep -q "REP widget ok" $OUT/logcat.txt && grep -q "com.qsentry.reproductor/com.qsentry.reproductor.PlayerWidget" $OUT/widgets.txt && echo "OK widget registrado y actualizándose" || echo "REVISAR widget"
  cat $OUT/e2e.txt 2>/dev/null
  if [ -f /tmp/deleted-title.txt ]; then T=$(cat /tmp/deleted-title.txt); grep -q "title=$T" $OUT/mediastore-final.txt && echo "FALLO el archivo sigue en el teléfono" || echo "OK el archivo ya no existe en el teléfono ($T)"; fi
  grep -q "FATAL EXCEPTION" $OUT/logcat-completo.txt && echo "FALLO crash detectado" || echo "OK sin crashes"
} | tee $OUT/RESUMEN.txt
rm -f $OUT/logcat-completo.txt
exit 0
