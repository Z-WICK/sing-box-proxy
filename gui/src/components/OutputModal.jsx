import { useEffect, useState } from 'react';

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
      <div className="modal wide" role="dialog" aria-label={title}>
        <div className="modal-head">
          <h2>{title}</h2>
          <div className="actions">
            <button type="button" className="btn small" onClick={copy} disabled={!text}>
              {copied ? '已复制' : '复制全部'}
            </button>
            <button type="button" className="btn small" onClick={onClose}>
              关闭
            </button>
          </div>
        </div>
        {loading && <p className="muted">正在从服务器读取…</p>}
        {error && <div className="banner error">{error}</div>}
        {!loading && !error && <pre className="output">{text || '（无输出）'}</pre>}
      </div>
    </div>
  );
}
