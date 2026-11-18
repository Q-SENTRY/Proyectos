// Genera los iconos de Android a partir de los SVG de la marca.
// Uso: node render.js   (desde reproductor-musica/branding)
const {chromium} = require('playwright');
const fs = require('fs'), path = require('path');
const RES = path.join(__dirname, '..', 'native', 'res');
const svg = f => fs.readFileSync(path.join(__dirname, f), 'utf8');
const D = {mdpi:1, hdpi:1.5, xhdpi:2, xxhdpi:3, xxxhdpi:4};

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  async function render(markup, size, out, {round=false, pad=0, bg='transparent'} = {}){
    await p.setViewportSize({width:size, height:size});
    await p.setContent(`<html><body style="margin:0;background:${bg}"><div style="width:${size}px;height:${size}px;overflow:hidden;${round?'border-radius:50%;':''}box-sizing:border-box;padding:${pad}px">${markup.replace('<svg ', `<svg width="${size-2*pad}" height="${size-2*pad}" `)}</div></body></html>`);
    fs.mkdirSync(path.dirname(out), {recursive:true});
    await p.screenshot({path:out, omitBackground:bg==='transparent', clip:{x:0,y:0,width:size,height:size}});
  }
  for (const [d, k] of Object.entries(D)) {
    const dir = path.join(RES, 'mipmap-' + d);
    await render(svg('logo.svg'), 48*k, path.join(dir, 'ic_launcher.png'));
    await render(svg('logo.svg').replace(/rx="118"/g, 'rx="256"'), 48*k, path.join(dir, 'ic_launcher_round.png'));
    await render(svg('glyph.svg'), 108*k, path.join(dir, 'ic_launcher_foreground.png'));
    await render(svg('bg.svg'), 108*k, path.join(dir, 'ic_launcher_bg.png'));
  }
  // Logo para la pantalla de inicio (splash)
  await render(svg('logo.svg'), 288, path.join(RES, 'drawable-xxhdpi', 'splash_logo.png'));
  // Vista previa
  await render(svg('logo.svg'), 512, path.join(__dirname, 'logo-512.png'));
  await b.close();
  console.log('iconos generados');
})();
