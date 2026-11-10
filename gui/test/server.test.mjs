import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, describe, it } from 'node:test';
import { gunzipSync } from 'node:zlib';
import { createApp, isAllowedOrigin, isLoopbackHost, tokenMatches } from '../server/index.mjs';
import { agentCommand, buildBundle, buildTar, remoteAsRoot, shq, sshArgs } from '../server/ssh.mjs';
import { ServerStore } from '../server/store.mjs';
import { isValidUnit, parseLogLines, validateServer } from '../server/validate.mjs';

const REPO_ROOT = new URL('../../', import.meta.url).pathname;

describe('validateServer', () => {
  it('accepts a minimal entry and normalizes empty fields to null', () => {
    const r = validateServer({ name: ' 东京 ', host: '203.0.113.10', port: '', user: '' });
    assert.deepEqual(r, { ok: true, value: { name: '东京', host: '203.0.113.10', port: null, user: null, identityFile: null } });
  });

  it('rejects ssh option injection in host and user', () => {
    assert.equal(validateServer({ name: 'x', host: '-oProxyCommand=evil' }).ok, false);
    assert.equal(validateServer({ name: 'x', host: 'a b' }).ok, false);
    assert.equal(validateServer({ name: 'x', host: 'h', user: '-oFoo' }).ok, false);
  });

  it('validates port range and identity path', () => {
    assert.equal(validateServer({ name: 'x', host: 'h', port: 70000 }).ok, false);
    assert.equal(validateServer({ name: 'x', host: 'h', identityFile: 'relative/key' }).ok, false);
    const r = validateServer({ name: 'x', host: 'h', identityFile: '~/.ssh/id' });
    assert.ok(r.ok && r.value.identityFile.endsWith('/.ssh/id') && !r.value.identityFile.startsWith('~'));
  });

  it('checks units and log line counts', () => {
    assert.ok(isValidUnit('sing-box-anytls.service'));
    assert.ok(!isValidUnit('sing-box;rm.service'));
    assert.ok(!isValidUnit('-x.service'));
    assert.equal(parseLogLines(undefined), 200);
    assert.equal(parseLogLines('6000'), null);
  });
});

describe('shell quoting', () => {
  it('round-trips arbitrary strings through sh', () => {
    for (const value of ["it's", '$(id)', '`x`', 'a"b', 'line\nbreak', '中文']) {
      const out = execFileSync('sh', ['-c', `printf %s ${shq(value)}`]).toString();
      assert.equal(out, value);
    }
  });

  it('builds a root wrapper that runs the command when already root-equivalent', () => {
    const cmd = remoteAsRoot(`printf %s ${shq('ok')}`).replace('"$(id -u)" -eq 0', '0 -eq 0');
    assert.equal(execFileSync('sh', ['-c', cmd]).toString(), 'ok');
    assert.match(agentCommand(['status']), /--agent/);
  });

  it('terminates ssh options before the host', () => {
    const args = sshArgs({ host: 'example.com', port: 2222, user: 'root', identityFile: null });
    assert.deepEqual(args.slice(-2), ['--', 'example.com']);
    assert.ok(args.includes('BatchMode=yes'));
  });
});

describe('script bundle', () => {
  it('produces a tar archive the system tar can list and extract', async () => {
    const bundle = await buildBundle(REPO_ROOT);
    assert.match(bundle.hash, /^[0-9a-f]{64}$/);
    const dir = mkdtempSync(join(tmpdir(), 'sbp-tar-'));
    try {
      const tarPath = join(dir, 'b.tar');
      writeFileSync(tarPath, gunzipSync(bundle.archive));
      const listing = execFileSync('tar', ['-tf', tarPath]).toString();
      assert.match(listing, /scripts\/sing-box-proxy-manager\.sh/);
      assert.match(listing, /scripts\/modules\/snell\.sh/);
      execFileSync('tar', ['-xf', tarPath, '-C', dir]);
      const extracted = readFileSync(join(dir, 'scripts/sing-box-proxy-manager.sh'));
      assert.deepEqual(extracted, readFileSync(join(REPO_ROOT, 'scripts/sing-box-proxy-manager.sh')));
      assert.ok(statSync(join(dir, 'scripts/sing-box-proxy-manager.sh')).mode & 0o100);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('pads entries to 512-byte blocks', () => {
    const tar = buildTar([{ path: 'a.txt', content: Buffer.from('hi') }], 0);
    assert.equal(tar.length, 512 + 512 + 1024);
  });
});

describe('access control', () => {
  it('only accepts loopback hosts and origins', () => {
    assert.ok(isLoopbackHost('127.0.0.1:8787'));
    assert.ok(isLoopbackHost('localhost:5173'));
    assert.ok(!isLoopbackHost('evil.example:8787'));
    assert.ok(!isLoopbackHost(undefined));
    assert.ok(isAllowedOrigin('http://127.0.0.1:8787'));
    assert.ok(!isAllowedOrigin('http://evil.example'));
    assert.ok(!isAllowedOrigin('null'));
  });

  it('compares tokens safely', () => {
    assert.ok(tokenMatches('abc', 'abc'));
    assert.ok(!tokenMatches('abc', 'abd'));
    assert.ok(!tokenMatches('abc', 'ab'));
    assert.ok(!tokenMatches('abc', undefined));
  });

  const configDir = mkdtempSync(join(tmpdir(), 'sbp-store-'));
  after(() => rmSync(configDir, { recursive: true, force: true }));

  async function startApp() {
    const store = await new ServerStore(configDir).load();
    const app = createApp({ store, syncer: { forget() {}, ensure: async () => ({ synced: false }) }, token: 'secret' });
    const server = createServer((req, res) => app.handle(req, res));
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    return { server, base: `http://127.0.0.1:${server.address().port}`, store };
  }

  it('rejects API calls without the token and supports CRUD with it', async () => {
    const { server, base, store } = await startApp();
    try {
      assert.equal((await fetch(`${base}/api/servers`)).status, 401);
      const headers = { 'x-sbp-token': 'secret', 'content-type': 'application/json' };
      const bad = await fetch(`${base}/api/servers`, { method: 'POST', headers, body: JSON.stringify({ name: 'x', host: '-bad' }) });
      assert.equal(bad.status, 400);
      const created = await fetch(`${base}/api/servers`, { method: 'POST', headers, body: JSON.stringify({ name: 'a', host: 'h' }) });
      assert.equal(created.status, 201);
      const { server: s } = await created.json();
      assert.equal(store.list().length, 1);
      assert.equal(statSync(store.file).mode & 0o777, 0o600);
      const svc = await fetch(`${base}/api/servers/${s.id}/service`, { method: 'POST', headers, body: JSON.stringify({ unit: 'x.service', action: 'mask' }) });
      assert.equal(svc.status, 400);
      const del = await fetch(`${base}/api/servers/${s.id}`, { method: 'DELETE', headers });
      assert.equal(del.status, 200);
      assert.equal(store.list().length, 0);
    } finally {
      server.close();
    }
  });
});

describe('ssh config parsing', async () => {
  const { parseHostAliases, parseSshG, detectAgent, splitArgs, readHostAliases } = await import('../server/sshconfig.mjs');

  it('extracts aliases, skipping wildcard and negated patterns', () => {
    const text = [
      'Host *',
      '  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"',
      'Host malibu',
      '  HostName 1.2.3.4',
      'Host bisai 60.205.95.144',
      'Host *.internal !bad',
      '# Host commented',
      'host=lower',
    ].join('\n');
    assert.deepEqual(parseHostAliases(text), [
      { alias: 'malibu', otherNames: [] },
      { alias: 'bisai', otherNames: ['60.205.95.144'] },
      { alias: 'lower', otherNames: [] },
    ]);
  });

  it('splits quoted arguments', () => {
    assert.deepEqual(splitArgs('"a b" c'), ['a b', 'c']);
  });

  it('parses ssh -G output and detects 1Password', () => {
    const g = parseSshG('hostname 1.2.3.4\nuser root\nport 22\nidentityfile ~/.ssh/a\nidentityfile ~/.ssh/b\nidentityagent ~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\n');
    assert.equal(g.hostname, '1.2.3.4');
    assert.deepEqual(g.identityfile, ['~/.ssh/a', '~/.ssh/b']);
    assert.equal(detectAgent(g.identityagent, ''), '1password');
    assert.equal(detectAgent(undefined, '/tmp/agent.sock'), 'agent');
    assert.equal(detectAgent('none', '/tmp/x'), 'none');
    assert.equal(detectAgent('SSH_AUTH_SOCK', '/x/1password/agent.sock'), '1password');
  });

  it('follows Include directives with globs', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'sbp-sshcfg-'));
    try {
      writeFileSync(join(dir, 'config'), `Host first\nInclude ${dir}/conf.d/*.conf\nHost last\n`);
      execFileSync('mkdir', ['-p', join(dir, 'conf.d')]);
      writeFileSync(join(dir, 'conf.d', 'b.conf'), 'Host bee\n');
      writeFileSync(join(dir, 'conf.d', 'a.conf'), 'Host ay\nHost first\n');
      const aliases = (await readHostAliases(join(dir, 'config'))).map((a) => a.alias);
      assert.deepEqual(aliases, ['first', 'ay', 'bee', 'last']);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
