// Prueba de extremo a extremo en el emulador: maneja la app real (WebView) con Playwright para Android.
// Verifica la carpeta WhatsApp y el borrado de archivos con el diálogo de confirmación de Android.
const { _android: android } = require('playwright-core');
const fs = require('fs');
const out = [];
const ok = (name, cond) => { const l = (cond ? 'OK ' : 'FALLO ') + name; console.log(l); out.push(l); };
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  let device;
  try {
    [device] = await android.devices();
    const webview = await device.webView({ pkg: 'com.qsentry.reproductor' }, { timeout: 30000 });
    const page = await webview.page();
    const logs = []; page.on('console', m => logs.push(m.text()));
    await page.waitForSelector('#allSongs .song', { timeout: 30000 });
    if (process.argv[2] === 'play') {
      // Paso 1: tocar la primera canción y abrir el reproductor
      await page.click('#allSongs .song .info'); await sleep(4000);
      fs.writeFileSync('test-results/2-reproduciendo-mini.png', await device.screenshot());
      await page.click('#mini .info'); await sleep(2500);
      fs.writeFileSync('test-results/3-reproductor.png', await device.screenshot());
      // Adelantar dentro de una canción del teléfono (barra de progreso y "retomar donde te quedaste")
      const seek = await page.evaluate(async () => {
        const a = [...document.querySelectorAll('audio')].find(x => !x.paused); if (!a) return 'sin audio';
        a.currentTime = 7; await new Promise(r => setTimeout(r, 1500)); return a.currentTime;
      });
      ok('adelantar la canción (posición tras saltar a 0:07: ' + (typeof seek === 'number' ? seek.toFixed(1) : seek) + ')', typeof seek === 'number' && seek >= 7);
      ok('toca canción y abre reproductor', logs.some(l => l.includes('REP play')) || await page.evaluate(() => [...document.querySelectorAll('audio')].some(a => !a.paused)));
      return;
    }
    if (process.argv[2] === 'bg') {
      // Con la app en segundo plano: ¿el sonido realmente fluye?
      const r = await page.evaluate(async () => {
        const a = [...document.querySelectorAll('audio')].find(x => !x.paused);
        const t0 = a ? a.currentTime : -1;
        await new Promise(res => setTimeout(res, 2000));
        const t1 = a ? a.currentTime : -1;
        let energy = -1, state = 'sin AudioContext';
        if (typeof actx !== 'undefined' && actx) { state = actx.state; const d = new Uint8Array(analyser.frequencyBinCount); analyser.getByteFrequencyData(d); energy = d.reduce((x, y) => x + y, 0); }
        return { hidden: document.hidden, avanza: +(t1 - t0).toFixed(2), state, energy };
      });
      ok(`segundo plano: la canción avanza ${r.avanza}s en 2s (app oculta: ${r.hidden})`, r.avanza > 1);
      ok(`segundo plano: motor de audio ${r.state}, señal ${r.energy}`, r.state === 'running' && r.energy > 0);
      return;
    }
    await page.evaluate(() => { document.querySelectorAll('.sheet.show,.player.open').forEach(e => e.classList.remove('show', 'open')); document.getElementById('scrim').classList.remove('show'); });

    const main = await page.$$eval('#allSongs .song .t', e => e.map(x => x.textContent));
    ok('biblioteca sin audios de WhatsApp (' + main.join(', ') + ')', main.length > 0 && !main.some(t => /WA\d|beep/i.test(t)));
    const wa = await page.$('.folder.wa');
    const waCount = wa ? await wa.$eval('small', e => e.textContent) : '';
    ok('carpeta WhatsApp creada: ' + waCount, !!wa && parseInt(waCount) >= 2);
    await page.screenshot({ path: 'test-results/6-biblioteca-whatsapp.png' });

    await wa.click(); await sleep(1200);
    const list = await page.$$eval('#lSongs .song .t', e => e.map(x => x.textContent));
    ok('dentro de WhatsApp: ' + list.join(', '), list.length >= 2);
    await page.screenshot({ path: 'test-results/7-carpeta-whatsapp.png' });

    // Eliminar el primer audio del teléfono
    const target = list[0];
    await page.click('#lSongs .song:nth-of-type(1) [data-more]'); await sleep(700);
    await page.click('[data-a=rmphone]'); await sleep(700);
    await page.screenshot({ path: 'test-results/8-confirmar-borrado.png' });
    await page.click('#sOk'); await sleep(2500);

    // Diálogo del sistema de Android
    fs.writeFileSync('test-results/9-dialogo-android.png', await device.screenshot());
    let tapped = false;
    for (const t of ['Allow', 'Permitir', 'ALLOW']) {
      try { await device.tap({ text: t }, { timeout: 3000 }); tapped = true; break; } catch {}
    }
    if (!tapped) {
      // Respaldo: buscar el botón con uiautomator y tocar sus coordenadas
      const { execSync } = require('child_process');
      for (let k = 0; k < 3 && !tapped; k++) {
        try {
          execSync('adb shell uiautomator dump /sdcard/dlg.xml');
          const xml = execSync('adb shell cat /sdcard/dlg.xml').toString();
          const m = xml.match(/text="(?:Allow|Permitir|ALLOW)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/);
          if (m) { execSync(`adb shell input tap ${(+m[1] + +m[3]) >> 1} ${(+m[2] + +m[4]) >> 1}`); tapped = true; }
        } catch (e) { console.log('uiautomator: ' + e.message.split('\n')[0]); }
        if (!tapped) await sleep(1500);
      }
    }
    ok('diálogo de Android para confirmar el borrado', tapped);
    await sleep(3000);
    const after = await page.$$eval('#lSongs .song .t', e => e.map(x => x.textContent)).catch(() => []);
    ok(`"${target}" eliminado (quedan: ${after.join(', ') || 'ninguno'})`, logs.some(l => l.includes('REP delete ok')) && !after.includes(target));
    await page.screenshot({ path: 'test-results/10-despues-de-borrar.png' });
    fs.writeFileSync('/tmp/deleted-title.txt', target);
  } catch (e) {
    ok('error en la prueba: ' + e.message.split('\n')[0], false);
  } finally {
    fs.appendFileSync('test-results/e2e.txt', out.join('\n') + '\n');
    if (device) await device.close().catch(() => {});
    process.exit(0);
  }
})();
