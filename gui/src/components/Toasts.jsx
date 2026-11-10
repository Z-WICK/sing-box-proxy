import Icon from './Icon.jsx';

export default function Toasts({ toasts, onDismiss }) {
  return (
    <div className="toasts" role="status" aria-live="polite">
      {toasts.map((t) => (
        <div key={t.id} className={`toast toast-${t.kind}`}>
          <span className="toast-text">{t.text}</span>
          <button type="button" className="icon-btn ghost" onClick={() => onDismiss(t.id)} aria-label="关闭提示">
            <Icon name="close" size={14} />
          </button>
        </div>
      ))}
    </div>
  );
}
