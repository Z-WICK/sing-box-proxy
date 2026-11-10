import { useEffect, useState } from 'react';
import Icon from './Icon.jsx';

export default function OutputModal({ title, text, loading, error, onClose }) {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal wide" role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head">
          <h2>{title}</h2>
          <div className="actions">
            <button type="button" className="btn small" onClick={copy} disabled={!text}>
              <Icon name={copied ? 'check' : 'copy'} size={14} />
              {copied ? '已复制' : '复制全部'}
            </button>
            <button type="button" className="icon-btn ghost" onClick={onClose} aria-label="关闭">
              <Icon name="close" />
            </button>
          </div>
        </div>
        {loading && <div className="skeleton-list"><span /><span /><span /></div>}
        {error && <div className="banner error">{error}</div>}
        {!loading && !error && <pre className="output">{text || '没有输出。'}</pre>}
      </div>
    </div>
  );
}
