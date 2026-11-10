import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, describe, it } from 'node:test';
import { ACTIONS, buildAnswers, initialValues, validateForm, visibleFields } from '../src/actions.js';
import { EXIT_MARK, createApp } from '../server/index.mjs';
import { ServerStore } from '../server/store.mjs';
import { RUN_ACTIONS, validateAnswers } from '../server/validate.mjs';

describe('action catalog', () => {
  it('only uses actions the server allows', () => {
    assert.deepEqual(Object.keys(ACTIONS).sort(), [...RUN_ACTIONS].sort());
  });

  it('builds answers from visible, non-empty fields plus fixed answers', () => {
    const action = ACTIONS['snell.configure'];
    const values = { ...initialValues(action), snell_version: '4', snell_port: ' 40000 ', snell_mode: 'unshaped', snell_obfs: 'tls', snell_obfs_host: 'a.com' };
    const answers = buildAnswers(action, values, { installed: false });
    assert.equal(answers.snell_port, '40000');
    assert.equal(answers.snell_obfs_host, 'a.com');
    assert.equal(answers.keep_existing, 'n');
    assert.ok(!('snell_mode' in answers), 'v6-only field must be hidden for v4');
    assert.ok(!('snell_psk' in answers), 'empty fields are not sent');
  });

  it('converts checkboxes to y/n and enforces typed confirmation', () => {
    const action = ACTIONS['singbox.uninstall'];
    const values = initialValues(action);
    assert.match(validateForm(action, values, { installed: true }), /UNINSTALL/);
    values.confirm_text = 'UNINSTALL';
    assert.equal(validateForm(action, values, { installed: true }), '');
    const answers = buildAnswers(action, values, { installed: true });
    assert.equal(answers.delete_binary, 'y');
    assert.equal(answers.delete_config_dir, 'n');
    assert.equal(answers.confirm, 'y');
  });

  it('requires a Reality server name only for new installs', () => {
    const action = ACTIONS['vless_reality.configure'];
    const values = initialValues(action);
    assert.match(validateForm(action, values, { installed: false }), /伪装域名/);
    assert.equal(validateForm(action, values, { installed: true }), '');
    assert.ok(!visibleFields(action, values, { installed: false }).some((f) => f.key === 'reuse_private_key'));
  });

  it('rejects non-numeric ports', () => {
    const action = ACTIONS['snell.configure'];
    assert.match(validateForm(action, { ...initialValues(action), snell_port: '12ab' }, { installed: true }), /数字/);
  });
});

describe('validateAnswers', () => {
  it('drops empty values and rejects bad keys or multi-line values', () => {
    assert.deepEqual(validateAnswers({ a_1: 'x', b: '', c: null }), { ok: true, value: [['a_1', 'x']] });
    assert.equal(validateAnswers({ 'Bad-Key': 'x' }).ok, false);
    assert.equal(validateAnswers({ a: 'x\ny' }).ok, false);
    assert.equal(validateAnswers(['x']).ok, false);
  });
});

describe('run endpoint', () => {
  const configDir = mkdtempSync(join(tmpdir(), 'sbp-run-'));
  after(() => rmSync(configDir, { recursive: true, force: true }));

  it('streams output, passes answers via stdin and blocks concurrent runs', async () => {
    const store = await new ServerStore(configDir).load();
    const srv = await store.add({ name: 'a', host: 'h', port: null, user: null, identityFile: null });
    const calls = [];
    let release;
    const gate = new Promise((r) => {
      release = r;
    });
    const stream = async (server, command, { input, onData }) => {
      calls.push({ command, input });
      onData(Buffer.from('[INFO] 开始执行\n'));
      await gate;
      onData(Buffer.from('[ OK ] 完成\n'));
      return { code: 0, stderr: '' };
    };
    const app = createApp({ store, syncer: { forget() {}, ensure: async () => ({ synced: false }) }, token: 't', stream });
    const http = createServer((req, res) => app.handle(req, res));
    await new Promise((r) => http.listen(0, '127.0.0.1', r));
    const base = `http://127.0.0.1:${http.address().port}/api/servers/${srv.id}/run`;
    const headers = { 'x-sbp-token': 't', 'content-type': 'application/json' };
    try {
      const bad = await fetch(base, { method: 'POST', headers, body: JSON.stringify({ action: 'rm.everything' }) });
      assert.equal(bad.status, 400);

      const first = fetch(base, {
        method: 'POST',
        headers,
        body: JSON.stringify({ action: 'snell.configure', answers: { snell_port: '40000', snell_psk: 'p=1' } }),
      });
      await new Promise((r) => setTimeout(r, 50));
      const second = await fetch(base, { method: 'POST', headers, body: JSON.stringify({ action: 'snell.update' }) });
      assert.equal(second.status, 409);

      release();
      const text = await (await first).text();
      assert.match(text, /开始执行[\s\S]*完成/);
      assert.ok(text.endsWith(`${EXIT_MARK}0\n`));
      assert.equal(calls.length, 1);
      assert.match(calls[0].command, /run.*snell\.configure.*--answers-stdin/);
      assert.equal(calls[0].input, 'snell_port=40000\nsnell_psk=p=1\n');
      assert.ok(!calls[0].command.includes('40000'), 'answers must not appear on the command line');
    } finally {
      http.close();
    }
  });
});
