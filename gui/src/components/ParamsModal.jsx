import { useEffect, useMemo, useState } from 'react';
import { PROTOCOL_LABELS } from '../api.js';
import {
  findEndpoint,
  findShareLink,
  isCodeLike,
  isPath,
  isSecretKey,
  noteTone,
  parseParams,
  sectionLabel,
} from '../params.js';
import Icon from './Icon.jsx';
import QrCode from './QrCode.jsx';

const PROTOCOL_GLYPHS = { anytls: 'AT', vless_reality: 'VR', socks5: 'S5', snell: 'SN', trusttunnel: 'TT' };

function useCopy() {
  const [copied, setCopied] = useState('');
  async function copy(id, text) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(id);
      setTimeout(() => setCopied((c) => (c === id ? '' : c)), 1400);
    } catch {
      setCopied('');
    }
  }
  return [copied, copy];
}

function CopyButton({ id, text, copied, onCopy, label = '复制' }) {
  const done = copied === id;
  return (
    <button
      type="button"
      className={`icon-btn ghost copy-btn ${done ? 'done' : ''}`}
      onClick={() => onCopy(id, text)}
      title={done ? '已复制' : label}
      aria-label={done ? '已复制' : label}
    >
      <Icon name={done ? 'check' : 'copy'} size={15} />
    </button>
  );
}

function Value({ item, id, copied, onCopy }) {
  const secret = isSecretKey(item.key);
  const [revealed, setRevealed] = useState(false);
  const bool = item.value === 'true' || item.value === 'false';

  let display;
  if (secret && !revealed) display = <span className="masked">{'•'.repeat(Math.min(16, item.value.length))}</span>;
  else if (bool) display = <span className={`pill ${item.value === 'true' ? 'pill-on' : ''}`}>{item.value === 'true' ? '是' : '否'}</span>;
  else display = <span className={`mono ${isPath(item.value) ? 'path' : ''}`}>{item.value}</span>;

  return (
    <div className="kv-row">
      <dt>{item.key}</dt>
      <dd>
        <span className="kv-value">{display}</span>
        <span className="kv-actions">
          {secret && (
            <button
              type="button"
              className="icon-btn ghost"
              onClick={() => setRevealed((v) => !v)}
              title={revealed ? '隐藏' : '显示'}
              aria-label={revealed ? '隐藏' : '显示'}
            >
              <Icon name={revealed ? 'eyeOff' : 'eye'} size={15} />
            </button>
          )}
          {!bool && <CopyButton id={id} text={item.value} copied={copied} onCopy={onCopy} />}
        </span>
      </dd>
    </div>
  );
}

function CodeBlock({ item, id, copied, onCopy, onQr }) {
  return (
    <div className="code-item">
      {item.key && <div className="code-label">{item.key}</div>}
      <div className="code-box">
        <code>{item.value}</code>
        <div className="code-actions">
          {onQr && (
            <button type="button" className="icon-btn ghost" onClick={onQr} title="显示二维码" aria-label="显示二维码">
              <Icon name="qr" size={15} />
            </button>
          )}
          <CopyButton id={id} text={item.value} copied={copied} onCopy={onCopy} />
        </div>
      </div>
    </div>
  );
}

function SectionView({ section, index, copied, onCopy, onQr }) {
  const code = section.items.filter((i) => index !== 0 && isCodeLike(i));
  const fields = section.items.filter((i) => !code.includes(i));
  return (
    <div className="section-view">
      {code.map((item, i) => (
        <CodeBlock
          key={`c${i}`}
          item={item}
          id={`${index}-c${i}`}
          copied={copied}
          onCopy={onCopy}
          onQr={/^[a-z][a-z0-9+.-]*:\/\//i.test(item.value) ? () => onQr(item) : null}
        />
      ))}
      {fields.length > 0 && (
        <dl className="kv">
          {fields.map((item, i) =>
            item.key ? (
              <Value key={`f${i}`} item={item} id={`${index}-f${i}`} copied={copied} onCopy={onCopy} />
            ) : (
              <CodeBlock key={`f${i}`} item={item} id={`${index}-f${i}`} copied={copied} onCopy={onCopy} />
            ),
          )}
        </dl>
      )}
    </div>
  );
}

export default function ParamsModal({ title, protocol, unit, text, loading, error, onClose }) {
  const parsed = useMemo(() => parseParams(text), [text]);
  const structured = parsed.sections.length > 0;
  const share = useMemo(() => findShareLink(parsed), [parsed]);
  const endpoint = useMemo(() => findEndpoint(parsed), [parsed]);
  const [tab, setTab] = useState(0);
  const [qr, setQr] = useState(null);
  const [copied, copy] = useCopy();

  useEffect(() => {
    const onKey = (e) => {
      if (e.key !== 'Escape') return;
      if (qr) setQr(null);
      else onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, qr]);

  const rawIndex = parsed.sections.length;
  const activeTab = structured ? tab : rawIndex;

  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal params-modal" role="dialog" aria-modal="true" aria-label={title}>
        <div className="params-head">
          <span className={`proto-tile proto-${protocol}`} aria-hidden="true">
            {PROTOCOL_GLYPHS[protocol] || '··'}
          </span>
          <div className="params-title">
            <h2>{PROTOCOL_LABELS[protocol] || title}</h2>
            <p className="mono">{unit}</p>
          </div>
          <div className="actions">
            <button type="button" className="btn small" onClick={() => copy('all', text)} disabled={!text}>
              <Icon name={copied === 'all' ? 'check' : 'copy'} size={14} />
              {copied === 'all' ? '已复制' : '复制全部'}
            </button>
            <button type="button" className="icon-btn ghost" onClick={onClose} aria-label="关闭">
              <Icon name="close" />
            </button>
          </div>
        </div>

        {loading && <div className="skeleton-list params-skeleton"><span /><span /><span /></div>}
        {error && <div className="banner error">{error}</div>}

        {!loading && !error && (
          <>
            {structured && (endpoint || share) && (
              <section className="share">
                {share && (
                  <button type="button" className="share-qr" onClick={() => setQr(share)} title="放大二维码">
                    <QrCode value={share.value} size={132} label={`${share.label} 二维码`} />
                  </button>
                )}
                <div className="share-body">
                  {endpoint && (
                    <div className="share-endpoint">
                      <span className="mono">{endpoint}</span>
                      <CopyButton id="endpoint" text={endpoint} copied={copied} onCopy={copy} label="复制地址" />
                    </div>
                  )}
                  {share && (
                    <>
                      <p className="share-hint">用手机客户端扫描左侧二维码，或复制下面的链接导入。</p>
                      <div className="code-box share-link">
                        <code>{share.value}</code>
                        <div className="code-actions">
                          <CopyButton id="share" text={share.value} copied={copied} onCopy={copy} label="复制链接" />
                        </div>
                      </div>
                    </>
                  )}
                </div>
              </section>
            )}

            <div className="params-tabs" role="tablist">
              {parsed.sections.map((s, i) => (
                <button
                  type="button"
                  role="tab"
                  key={s.title}
                  aria-selected={activeTab === i}
                  className={activeTab === i ? 'active' : ''}
                  onClick={() => setTab(i)}
                >
                  {sectionLabel(s.title, i)}
                </button>
              ))}
              <button
                type="button"
                role="tab"
                aria-selected={activeTab === rawIndex}
                className={`raw-tab ${activeTab === rawIndex ? 'active' : ''}`}
                onClick={() => setTab(rawIndex)}
              >
                原始文本
              </button>
            </div>

            <div className="params-body">
              {activeTab === rawIndex ? (
                <pre className="output">{text || '没有输出。'}</pre>
              ) : (
                <SectionView
                  section={parsed.sections[activeTab]}
                  index={activeTab}
                  copied={copied}
                  onCopy={copy}
                  onQr={(item) => setQr({ value: item.value, label: item.key || parsed.sections[activeTab].title })}
                />
              )}
            </div>

            {parsed.notes.map((note, i) => (
              <div key={i} className={`callout callout-${noteTone(note)}`}>
                <Icon name={noteTone(note) === 'warn' ? 'shield' : 'info'} size={16} />
                <span>{note}</span>
              </div>
            ))}
          </>
        )}

        {qr && (
          <div className="qr-overlay" onMouseDown={(e) => e.target === e.currentTarget && setQr(null)}>
            <div className="qr-card">
              <QrCode value={qr.value} size={qr.value.length > 600 ? 440 : 280} label={`${qr.label} 二维码`} />
              <p>{qr.label}</p>
              <button type="button" className="btn small" onClick={() => setQr(null)}>
                关闭
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
