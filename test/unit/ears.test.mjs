// The microphone helper's channel choice (native/ears ChannelPicker.swift), compiled with a small
// driver (test/swift/channel-picker.swift). Needs the Swift compiler, so it runs on macOS only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const hasSwift = process.platform === 'darwin' && spawnSync('swiftc', ['--version'], { encoding: 'utf8' }).status === 0;

test('the mic helper hears the loudest input channel, steadily, and never a loopback input', { skip: !hasSwift && 'needs swiftc (macOS)' }, () => {
  const bin = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'jarvis-ears-')), 'picker');
  const src = [path.join(ROOT, 'native/ears/Sources/JarvisEars/ChannelPicker.swift'), path.join(ROOT, 'test/swift/channel-picker.swift')];
  const built = spawnSync('swiftc', ['-O', '-parse-as-library', '-o', bin, ...src], { encoding: 'utf8' });
  assert.equal(built.status, 0, built.stderr);
  const r = JSON.parse(spawnSync(bin, { encoding: 'utf8' }).stdout);
  const all = (x, c) => x.heard.every((h) => h === c);
  assert.ok(all(r.interface, 0) && r.interface.switches === 0, 'a 26-input interface: the mic on input 1, from the first buffer');
  assert.ok(all(r.second, 1) && r.second.switches === 0, 'the mic on input 2');
  assert.equal(r.stereo.switches, 0, 'a stereo mic does not hop between sides');
  assert.ok(all(r.loopback, 0), 'the loopback input, however loud, is never heard');
  assert.ok(all(r.knock, 0), 'one loud buffer elsewhere does not take over');
  assert.equal(r.moved.switches, 1, 'the mic moving to another input: one fade to it');
  assert.equal(r.moved.heard.at(-1), 3);
  assert.ok(r.moved.heard.indexOf(3) <= 24, 'and within a few buffers');
  assert.deepEqual(r.allSkipped.heard, [1], 'everything skipped: still the loudest');
});
