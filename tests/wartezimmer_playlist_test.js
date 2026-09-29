// Regressionstest der eingebetteten Video-Logik; keine Dienste oder Downloads.
// Aufruf: node tests/wartezimmer_playlist_test.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const installer = fs.readFileSync(path.join(__dirname, '..', 'wartezimmer.sh'), 'utf8');
const script = installer.split('<script>\n')[1].split('</script>')[0]
  .replace(/\\([$`\\])/g, '$1');
new vm.Script(script); // Auch den vollständigen, unveränderten Browsercode prüfen.
const init = script.lastIndexOf('  await loadConfig();\n  await startNormalMode();');
assert.ok(init > 0);
const testScript = script.slice(0, init) + `
  globalThis.api = {
    loadConfig, startNormalMode, pauseNormal, resumeNormal, skipVideo,
    state: () => ({playlist: [...playlist], idx, video: videoEl, image: imgEl})
  };
})();`;

async function harness(files, config = {video_random_order: true}, seed = 17) {
  const intervals = new Map();
  let intervalId = 0;
  function element() {
    return {
      style: {}, innerHTML: '', volume: 1, muted: false,
      appendChild() {}, addEventListener() {}, pause() {},
      async play() {},
    };
  }
  const math = Object.create(Math);
  math.random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 4294967296;
  };
  const context = vm.createContext({
    Math: math, Date, encodeURIComponent,
    document: {getElementById: element, createElement: element},
    fetch: async url => ({
      ok: true,
      json: async () => url === 'wartezimmer.json' ? config : {files: [...files]},
    }),
    setInterval: callback => { intervals.set(++intervalId, callback); return intervalId; },
    clearInterval: id => intervals.delete(id),
    setTimeout: callback => { callback(); },
  });
  await vm.runInContext(testScript, context);
  await context.api.loadConfig();
  await context.api.startNormalMode();
  return {api: context.api, config, intervals};
}

const names = state => Array.from(state.playlist);

async function run() {
  for (const count of [0, 1, 2, 5]) {
    const files = ['A.mp4', 'B.m4v', 'C.mp4', 'D.mp4', 'Ä mit Leerzeichen.mp4'].slice(0, count);
    const {api} = await harness(files);
    if (!count) {
      await api.skipVideo('ended');
      assert.deepEqual(names(api.state()), []);
      continue;
    }
    let previous = null;
    const orders = new Set();
    for (let round = 0; round < 100; round++) {
      const played = [];
      for (let i = 0; i < count; i++) {
        const state = api.state();
        const current = state.playlist[state.idx];
        assert.equal(state.video.src, 'videos/' + encodeURIComponent(current));
        if (count > 1) assert.notEqual(current, previous);
        previous = current;
        played.push(current);
        await api.skipVideo('ended');
      }
      assert.deepEqual([...played].sort(), [...files].sort());
      orders.add(played.join('|'));
    }
    if (count > 2) assert.ok(orders.size > 1, 'Durchläufe müssen neu gemischt werden');
  }

  const files = ['A.mp4', 'B.mp4', 'C.mp4', 'D.mp4'];
  for (const config of [{}, {video_random_order: false}]) {
    const {api} = await harness(files, config);
    for (let i = 0; i < 12; i++) {
      assert.equal(api.state().video.src, 'videos/' + files[i % files.length]);
      await api.skipVideo('ended');
    }
  }

  const {api, config} = await harness(files);
  await api.skipVideo('ended');
  const before = api.state();
  api.pauseNormal();
  await api.resumeNormal();
  assert.deepEqual(names(api.state()), names(before));
  assert.equal(api.state().idx, before.idx);
  assert.equal(api.state().video, before.video);

  config.playlist_restart_on_call_end = true;
  await api.loadConfig();
  api.pauseNormal();
  await api.resumeNormal();
  assert.deepEqual(names(api.state()), names(before));
  assert.equal(api.state().idx, 0, 'Expliziter Playlist-Neustart behält die gemischte Reihenfolge');

  config.video_random_order = false;
  await api.loadConfig();
  for (let i = 0; i < files.length; i++) await api.skipVideo('ended');
  assert.deepEqual(names(api.state()), files);

  const images = ['A.jpg', 'B.png', 'C.jpg'];
  const slideshow = await harness(images, {mode: 'slideshow', video_random_order: true});
  assert.deepEqual(names(slideshow.api.state()), images);
  assert.equal(slideshow.api.state().image.src, 'images/A.jpg');
  const tick = [...slideshow.intervals.values()][0];
  tick();
  assert.equal(slideshow.api.state().image.src, 'images/B.png');
  console.log('OK: Shuffle-Durchläufe, Übergänge, 0/1 Video, alphabetischer Modus, Aufrufpausen und Bilder.');
}

run().catch(error => { console.error(error); process.exitCode = 1; });
