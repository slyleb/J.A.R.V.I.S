// Plays TTS buffers through Web Audio (with a level meter) and background
// music through an <audio> element. Driven entirely by the main process.
const ctx = new AudioContext();
const analyser = ctx.createAnalyser();
analyser.fftSize = 512;
// The voice's volume (Settings, the speaker button): after the meter, so the HUD still sees it speak.
const gain = ctx.createGain();
analyser.connect(gain);
gain.connect(ctx.destination);
const setVoiceVolume = (v) => { if (Number.isFinite(+v)) gain.gain.value = Math.max(0, Math.min(1, +v)); };
const samples = new Float32Array(analyser.fftSize);
let source = null;
let meter = null;

function stopTTS(notify) {
  if (source) { source.onended = null; try { source.stop(); } catch {} source = null; }
  clearInterval(meter);
  if (notify) host.send('tts-ended');
}

async function playTTS(data) {
  stopTTS(false);
  if (ctx.state === 'suspended') await ctx.resume();
  let buf;
  try {
    const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
    buf = await ctx.decodeAudioData(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  } catch (e) {
    host.send('log', `decode failed: ${e}`);
    host.send('tts-ended');
    return;
  }
  const src = ctx.createBufferSource();
  src.buffer = buf;
  src.connect(analyser);
  src.onended = () => { if (source === src) { source = null; clearInterval(meter); host.send('tts-level', 0); host.send('tts-ended'); } };
  source = src;
  src.start();
  meter = setInterval(() => {
    analyser.getFloatTimeDomainData(samples);
    let sum = 0;
    for (const s of samples) sum += s * s;
    const db = 20 * Math.log10(Math.sqrt(sum / samples.length) + 1e-6);
    host.send('tts-level', Math.max(0, Math.min(1, (db + 50) / 50)));
  }, 33);
}

// ---------- music ----------
const music = document.getElementById('music');
let reported = false;
music.addEventListener('timeupdate', () => {
  if (!reported && music.currentTime > 0.3) { reported = true; host.send('music-playing'); }
});
music.addEventListener('error', () => host.send('music-error', music.error ? `code ${music.error.code} ${music.error.message || ''}` : 'error'));
music.addEventListener('ended', () => host.send('music-ended'));

function playMusic(url, volume) {
  reported = false;
  music.src = url;
  music.volume = volume;
  music.play().catch((e) => host.send('music-error', String(e)));
}

function stopMusic() {
  music.pause();
  music.removeAttribute('src');
  music.load();
}

// Short two-tone chime when JARVIS wakes. soft: the quieter, quicker one when he listens again
// (over in about 0.2 s, inside the 0.4 s after his voice that the listener throws away).
function chime(soft) {
  const t = ctx.currentTime;
  const [peak, gap, len] = soft ? [0.05, 0.05, 0.12] : [0.18, 0.09, 0.22];
  for (const [f, d] of [[880, 0], [1320, gap]]) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.frequency.value = f;
    g.gain.setValueAtTime(0.0001, t + d);
    g.gain.exponentialRampToValueAtTime(peak, t + d + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + d + len);
    o.connect(g).connect(ctx.destination);
    o.start(t + d); o.stop(t + d + len + 0.03);
  }
}

host.on((msg) => {
  switch (msg.type) {
    case 'tts-play': setVoiceVolume(msg.volume); playTTS(msg.data); break;
    case 'tts-volume': setVoiceVolume(msg.v); break;
    case 'tts-stop': stopTTS(false); break;
    case 'music-play': playMusic(msg.url, msg.volume); break;
    case 'music-stop': stopMusic(); break;
    case 'music-volume': music.volume = Math.max(0, Math.min(1, msg.v)); break;
    case 'chime': chime(msg.soft); break;
  }
});
