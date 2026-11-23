import Icon from './Icon.jsx';

const TOAST_ICONS = {
  success: 'check',
  error: 'shield',
  info: 'info',
};

export default function Toasts({ toasts, onDismiss }) {
  return (
    <div className="toasts" role="status" aria-live="polite">
      {toasts.map((t) => (
        <div
          key={t.id}
          className={`toast toast-${t.kind}`}
          style={{ '--toast-duration': `${t.duration || (t.kind === 'error' ? 7000 : 3500)}ms` }}
        >
          <span className="toast-icon" aria-hidden="true">
            <Icon name={TOAST_ICONS[t.kind] || 'info'} size={15} />
          </span>
          <span className="toast-text">{t.text}</span>
          <button type="button" className="icon-btn ghost" onClick={() => onDismiss(t.id)} aria-label="关闭提示">
            <Icon name="close" size={14} />
          </button>
          <span className="toast-progress" aria-hidden="true" />
        </div>
      ))}
    </div>
  );
}
