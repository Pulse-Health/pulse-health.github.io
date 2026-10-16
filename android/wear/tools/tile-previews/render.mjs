// Draws the five tile preview images of the watch app (res/drawable-nodpi/tile_preview_*.png).
//
// A preview is the picture the watch's tile gallery shows before the user adds a tile. The tiles themselves are ProtoLayout trees that
// only a watch renders, so the previews are drawn here from the same words, colours and icons (TileUi.kt, the tile classes, the vector
// drawables) with the idealised preview data of widgets/fixtures/preview.json (the strings are the ones TileModelsTest asserts).
// Run it again when a tile's look or its sample data changes:
//
//     npm install --no-save playwright && npx playwright install chromium   (once)
//     node android/wear/tools/tile-previews/render.mjs
//
// 400 x 400 px is a 200 dp round watch face at 2x; the content stays inside the inscribed circle.
import { chromium } from 'playwright';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const wear = join(here, '..', '..');
const drawables = join(wear, 'src', 'main', 'res', 'drawable');
const out = join(wear, 'src', 'main', 'res', 'drawable-nodpi');
mkdirSync(out, { recursive: true });

/** The vector drawable `ic_<name>.xml` as an inline SVG that takes its colour from CSS `color`. */
function icon(name) {
  const xml = readFileSync(join(drawables, `ic_${name}.xml`), 'utf8');
  const [vw, vh] = ['viewportWidth', 'viewportHeight'].map((a) => xml.match(new RegExp(`android:${a}="([^"]+)"`))[1]);
  const paths = [...xml.matchAll(/<path\b([\s\S]*?)\/>/g)].map(([, attrs]) => {
    const get = (a) => (attrs.match(new RegExp(`android:${a}="([^"]*)"`)) || [])[1];
    const fill = get('fillColor');
    const stroke = get('strokeColor');
    const solid = (c) => (c && c.toUpperCase() !== '#00000000' ? 'currentColor' : 'none');
    return `<path d="${get('pathData')}" fill="${solid(fill)}" stroke="${solid(stroke)}" stroke-width="${get('strokeWidth') || 0}"`
      + ` stroke-linecap="${(get('strokeLineCap') || 'butt')}" stroke-linejoin="${(get('strokeLineJoin') || 'miter')}"/>`;
  });
  return `<svg viewBox="0 0 ${vw} ${vh}" xmlns="http://www.w3.org/2000/svg">${paths.join('')}</svg>`;
}

// The trend line of the lift tile (Sparkline.kt): evenly spaced points, highest at the top, a green line, the record as a larger gold dot.
function sparkline(values, recordIndex, width = 248, height = 80) {
  const inset = 10;
  const low = Math.min(...values);
  const high = Math.max(...values);
  const pts = values.map((v, i) => [
    inset + ((width - 2 * inset) * i) / (values.length - 1),
    inset + (height - 2 * inset) * (1 - (high === low ? 0.5 : (v - low) / (high - low))),
  ]);
  const line = pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x},${y}`).join(' ');
  const dots = pts.map(([x, y], i) => `<circle cx="${x}" cy="${y}" r="${i === recordIndex ? 9 : 5}" fill="${i === recordIndex ? '#FFD60A' : '#30D158'}"/>`).join('');
  return `<svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><path d="${line}" fill="none" stroke="#30D158" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>${dots}</svg>`;
}

// The heart-rate bars (HeartRateTile.kt): one column per bucket, effort solid, rest at half opacity, the tallest at full height.
function bars(bpms, efforts) {
  const low = Math.min(...bpms);
  const high = Math.max(...bpms);
  const count = bpms.length;
  const gap = 6;
  const width = Math.min(Math.max((248 - gap * (count - 1)) / count, 8), 28);
  return `<div class="bars" style="gap:${gap}px">${bpms
    .map((b, i) => {
      const h = Math.round(108 * (0.2 + 0.8 * ((b - low) / (high - low))));
      return `<i style="width:${width}px;height:${h}px;background:${efforts[i] ? '#FF453A' : 'rgba(255,69,58,.5)'}"></i>`;
    })
    .join('')}</div>`;
}

const tiles = {
  next_up: `
    <div class="label green">${icon('dumbbell')}<span>Push day</span></div>
    <div class="content"><div class="title3">Upper A · Push</div><div class="caption2 secondary">6 exercises · ~55 min</div></div>
    <div class="chip">Start</div>`,
  workout: `
    <div class="label secondary-label">Set 3 of 4</div>
    <div class="content"><div class="body1">Bench Press</div><div class="title1">80 kg × 6</div></div>
    <div class="chip">${icon('hand')}<span>Log set</span></div>`,
  record: `
    <div class="label gold">${icon('trophy')}<span>NEW RECORD</span></div>
    <div class="content"><div class="body1">Bench Press</div><div class="title1">85 × 5</div><div class="caption2 gold">e1RM 99 kg · +4 kg</div></div>`,
  lift_trend: `
    <div class="label green"><span>Bench Press</span></div>
    <div class="content">
      <div class="row"><div class="title1">96</div><div class="caption2 secondary">kg e1RM</div></div>
      <div class="spacer"></div>${sparkline([93, 99, 96], 1)}
    </div>
    <div class="caption2 secondary foot">3 sessions · −3 kg</div>`,
  heart_rate: `
    <div class="label heart">${icon('heart')}<span>Heart rate</span></div>
    <div class="content">${bars([96, 131, 104, 146, 101, 151, 108, 140], [false, true, false, true, false, true, false, true])}
      <div class="spacer"></div><div class="caption2 bold">avg 118 · peak 151</div></div>
    <div class="caption3 secondary foot">Upper B · Pull</div>`,
};

const html = `<!doctype html><meta charset="utf-8"><style>
  body { margin: 0; background: #444; }
  .tile { width: 400px; height: 400px; background: #000; color: #fff; box-sizing: border-box; padding: 54px 40px 50px;
    display: flex; flex-direction: column; align-items: center; text-align: center; overflow: hidden;
    font-family: Roboto, "Google Sans", Inter, "Helvetica Neue", Arial, sans-serif; }
  .tile.record { background: #3A2E00; }
  .label { display: flex; align-items: center; gap: 8px; font-size: 28px; font-weight: 700; height: 34px; }
  .label svg { width: 30px; height: 30px; }
  .green { color: #30D158; } .gold { color: #FFD60A; } .heart { color: #FF453A; }
  .secondary, .secondary-label { color: #98989D; } .secondary-label { font-weight: 400; }
  .content { flex: 1; display: flex; flex-direction: column; justify-content: center; align-items: center; gap: 2px; }
  .title1 { font-size: 48px; font-weight: 700; line-height: 1.1; } .title3 { font-size: 32px; font-weight: 700; line-height: 1.15; }
  .body1 { font-size: 32px; font-weight: 700; line-height: 1.15; }
  .caption2 { font-size: 24px; } .caption3 { font-size: 20px; } .bold { font-weight: 700; }
  .row { display: flex; align-items: baseline; gap: 8px; } .spacer { height: 8px; }
  .foot { margin-top: 2px; }
  .chip { height: 84px; width: 252px; border-radius: 42px; background: #30D158; color: #000; font-size: 30px; font-weight: 600;
    display: flex; align-items: center; justify-content: center; gap: 10px; }
  .chip svg { width: 30px; height: 30px; }
  .bars { display: flex; align-items: flex-end; height: 108px; } .bars i { display: block; border-radius: 4px; }
</style>${Object.entries(tiles).map(([name, body]) => `<div class="tile ${name}" id="${name}">${body}</div>`).join('')}`;

writeFileSync(join(here, 'tiles.html'), html);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 400, height: 400 }, deviceScaleFactor: 1 });
await page.setContent(html);
for (const name of Object.keys(tiles)) {
  const file = join(out, `tile_preview_${name}.png`);
  await page.locator(`#${name}`).screenshot({ path: file });
  console.log('wrote', file);
}
await browser.close();
