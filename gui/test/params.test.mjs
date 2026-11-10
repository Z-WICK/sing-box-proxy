import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { findEndpoint, findShareLink, isCodeLike, isSecretKey, noteTone, parseParams, sectionLabel } from '../src/params.js';

const ANYTLS = `
AnyTLS 导入参数：
  服务器      : 203.0.113.7
  端口        : 443
  内部监听    : 127.0.0.1:4443
  密码        : secretPassword123
  TLS         : true
  SNI         : 203.0.113.7
  跳过验证    : true

Surge:
  代理参数    : AnyTLS-sing-box-anytls = anytls, 203.0.113.7, 443, password=secretPassword123, sni=203.0.113.7, skip-cert-verify=true, reuse=true
  配置文件    : /root/sing-box-proxy/data/client-import/sing-box-anytls.surge.conf

Egern:
  AnyTLS URI   : anytls://secretPassword123@203.0.113.7:443?type=tcp&security=tls&sni=203.0.113.7&insecure=1#AnyTLS-sing-box-anytls
  URI 文件    : /root/sing-box-proxy/data/client-import/sing-box-anytls.egern.uri

Clash (Mihomo):
  配置文件    : /root/sing-box-proxy/data/client-import/sing-box-anytls.clash.yaml
  导入链接    : clash://install-config?url=http%3A%2F%2F203.0.113.7%3A18080%2Fx.yaml

安全提示：导入链接包含凭据和 token 参数，请勿外传。
`;

const SOCKS5 = `
SOCKS5 参数：
  服务名      : sing-box-socks5.service
  服务器      : 2001:db8::1
  端口        : 1080
  用户名      : proxy
  密码        : pw

SOCKS5 URI:
  socks5://proxy:pw@[2001:db8::1]:1080#SOCKS5-sing-box-socks5

测试命令：
  curl -x 'socks5h://proxy:pw@[2001:db8::1]:1080' https://api.ipify.org
`;

const SNELL = `
Snell 参数：
  状态        : active=active | enabled=enabled
  服务器      : 203.0.113.9
  端口        : 2345
  PSK         : abcdefghijkl

Surge 配置：
  Snell = snell, 203.0.113.9, 2345, psk=abcdefghijkl, version=6
`;

describe('parseParams', () => {
  it('splits sections, key/value rows and notes', () => {
    const p = parseParams(ANYTLS);
    assert.deepEqual(p.sections.map((s) => s.title), ['AnyTLS 导入参数', 'Surge', 'Egern', 'Clash (Mihomo)']);
    assert.deepEqual(p.sections[0].items[2], { key: '内部监听', value: '127.0.0.1:4443' });
    assert.equal(p.sections[1].items[0].key, '代理参数');
    assert.match(p.sections[1].items[0].value, /^AnyTLS-sing-box-anytls = anytls/);
    assert.deepEqual(p.notes, ['安全提示：导入链接包含凭据和 token 参数，请勿外传。']);
    assert.equal(noteTone(p.notes[0]), 'warn');
  });

  it('keeps values containing colons intact and treats bare lines as items', () => {
    const p = parseParams(SOCKS5);
    assert.equal(p.sections[0].items[1].value, '2001:db8::1');
    assert.deepEqual(p.sections[1].items, [{ key: null, value: 'socks5://proxy:pw@[2001:db8::1]:1080#SOCKS5-sing-box-socks5' }]);
    assert.match(p.sections[2].items[0].value, /^curl -x/);
    assert.equal(findEndpoint(p), '[2001:db8::1]:1080');
  });

  it('picks the protocol URI as the share link, not http or app links', () => {
    assert.match(findShareLink(parseParams(ANYTLS)).value, /^anytls:\/\//);
    assert.match(findShareLink(parseParams(SOCKS5)).value, /^socks5:\/\//);
    assert.equal(findShareLink(parseParams(SNELL)), null);
    assert.equal(findEndpoint(parseParams(SNELL)), '203.0.113.9:2345');
  });

  it('classifies secrets and code-like values', () => {
    assert.ok(isSecretKey('密码'));
    assert.ok(isSecretKey('PSK'));
    assert.ok(isSecretKey('UUID'));
    assert.ok(!isSecretKey('服务器'));
    assert.ok(isCodeLike({ key: '代理参数', value: 'x = y' }));
    assert.ok(isCodeLike({ key: null, value: 'Snell = snell' }));
    assert.ok(!isCodeLike({ key: '配置文件', value: '/root/x' }));
  });

  it('labels tabs and tolerates unstructured text', () => {
    assert.equal(sectionLabel('AnyTLS 导入参数', 0), '参数');
    assert.equal(sectionLabel('TrustTunnel TOML 客户端配置', 2), 'TrustTunnel 配置');
    assert.deepEqual(parseParams('just some text\nmore').sections, []);
    assert.deepEqual(parseParams('').sections, []);
  });
});
