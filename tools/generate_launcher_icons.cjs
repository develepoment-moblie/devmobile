// Native vector adaptation of the compass in the supplied Nova Paris logo.
// Rendered PNGs are Android's legacy launcher fallback; adaptive icons use vectors.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
let sharp;
try { sharp = require('sharp'); }
catch {
  sharp = require(path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'));
}
const root = path.resolve(__dirname, '..');
const res = path.join(root, 'android/app/src/main/res');
const gold = '#B69B5E', light = '#D8C99F', background = '#F7F3EA';
const paths = [
  // Interrupted orbit from the original compass emblem.
  [gold, 'M32.1 51 A22 22 0 0 1 48 32.8 L48 33.7 A21 21 0 0 0 33.2 51 Z M60 32.8 A22 22 0 0 1 75.9 51 L74.8 51 A21 21 0 0 0 60 33.7 Z M75.9 57 A22 22 0 0 1 60 75.2 L60 74.3 A21 21 0 0 0 74.8 57 Z M48 75.2 A22 22 0 0 1 32.1 57 L33.2 57 A21 21 0 0 0 48 74.3 Z'],
  // Four diagonal points, then the tall cardinal compass star.
  [light, 'M54 51 L42 41 L51 54 L42 67 L54 57 L67 67 L57 54 L67 41 Z'],
  [gold, 'M54 22 L55.6 51.5 L81 54 L55.6 56.5 L54 86 L52.4 56.5 L27 54 L52.4 51.5 Z'],
  [light, 'M54 22 L54 54 L55.6 51.5 Z M54 54 L81 54 L55.6 56.5 Z M54 54 L54 86 L52.4 56.5 Z M54 54 L27 54 L52.4 51.5 Z'],
  [gold, 'M67 35 L67.6 37.4 L70 38 L67.6 38.6 L67 41 L66.4 38.6 L64 38 L66.4 37.4 Z M40 66 L40.6 68.4 L43 69 L40.6 69.6 L40 72 L39.4 69.6 L37 69 L39.4 68.4 Z'],
  [light, 'M40 42 L40.4 43.6 L42 44 L40.4 44.4 L40 46 L39.6 44.4 L38 44 L39.6 43.6 Z M65 68 L65.4 69.6 L67 70 L65.4 70.4 L65 72 L64.6 70.4 L63 70 L64.6 69.6 Z'],
];
function write(relative, content) {
  const target = path.join(root, relative);fs.mkdirSync(path.dirname(target), {recursive:true});fs.writeFileSync(target, content);
}
const foreground = `<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n${paths.map(([color,d])=>`    <path android:fillColor="${color}" android:pathData="${d}"/>`).join('\n')}\n</vector>\n`;
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="108" height="108" viewBox="0 0 108 108"><rect width="108" height="108" fill="${background}"/>${paths.map(([color,d])=>`<path fill="${color}" d="${d}"/>`).join('')}</svg>`;
write('assets/images/nova_paris_icon.svg', svg+'\n');
write('android/app/src/main/res/drawable/ic_launcher_foreground.xml', foreground);
write('android/app/src/main/res/values/icon_colors.xml', `<resources><color name="ic_launcher_background">${background}</color></resources>\n`);
for (const [folder, monochrome] of [['mipmap-anydpi-v26',false],['mipmap-anydpi-v33',true]]) {
  write(`android/app/src/main/res/${folder}/ic_launcher.xml`, `<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background"/>\n    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n${monochrome?'    <monochrome android:drawable="@drawable/ic_launcher_foreground"/>\n':''}</adaptive-icon>\n`);
}
(async()=>{
  // Legacy images enlarge the same vector inside a baked safe margin.
  const legacy = svg.replace(/<path /g,'<path transform="translate(-13.5 -13.5) scale(1.25)" ');
  for (const [density,size] of [['mdpi',48],['hdpi',72],['xhdpi',96],['xxhdpi',144],['xxxhdpi',192]]) {
    await sharp(Buffer.from(legacy)).resize(size,size).png().toFile(path.join(res,`mipmap-${density}/ic_launcher.png`));
  }
  await sharp(Buffer.from(legacy)).resize(512,512).png().toFile(path.join(root,'verification/launcher-icon.png'));
  console.log('Nova Paris launcher icons generated: five legacy densities, adaptive and themed icons.');
})().catch(error=>{console.error(error);process.exitCode=1;});
