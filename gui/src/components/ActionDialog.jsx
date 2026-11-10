import { useEffect, useRef, useState } from 'react';
import { ACTIONS, buildAnswers, initialValues, validateForm, visibleFields } from '../actions.js';
import { runAction, stripAnsi } from '../api.js';
import Icon from './Icon.jsx';

function lineTone(line) {
  if (/^\[ERR \]/.test(line)) return 'err';
  if (/^\[WARN\]/.test(line)) return 'warn';
  if (/^\[ OK \]/.test(line)) return 'ok';
  if (/^\[INFO\]/.test(line)) return 'info';
  return '';
}

function Field({ field, value, onChange }) {
  const id = `f-${field.key}`;
  if (field.type === 'check') {
    return (
      <label className="check-field" htmlFor={id}>
        <input id={id} type="checkbox" checked={Boolean(value)} onChange={(e) => onChange(e.target.checked)} />
        <span>{field.label}</span>
      </label>
    );
  }
  return (
    <label className="form-field" htmlFor={id}>
      <span className="form-label">{field.label}</span>
      {field.type === 'select' ? (
        <select id={id} value={value} onChange={(e) => onChange(e.target.value)}>
          {field.options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      ) : (
        <input
          id={id}
          type={field.type === 'password' ? 'password' : 'text'}
          value={value}
          placeholder={field.placeholder}
          inputMode={field.inputMode}
          autoComplete="off"
          spellCheck="false"
          onChange={(e) => onChange(e.target.value)}
        />
      )}
      {field.hint && <span className="form-hint">{field.hint}</span>}
    </label>
  );
}

/** 把脚本错误里的答案键（如 snell_port）换成表单上的字段名称。 */
function friendlyError(line, action) {
  if (!line) return '';
  const text = line.replace(/^\[ERR \]\s*/, '');
  return text.replace(/参数 ([a-z0-9_]+)/, (m, key) => {
    const field = action.fields.find((f) => f.key === key);
    return field ? `「${field.label}」` : m;
  });
}

export default function ActionDialog({ server, actionId, installed, onClose, onFinished, onShowParams }) {
  const action = ACTIONS[actionId];
  const [values, setValues] = useState(() => initialValues(action));
  const [phase, setPhase] = useState('form'); // form | running | done
  const [error, setError] = useState('');
  const [log, setLog] = useState('');
  const [exitCode, setExitCode] = useState(null);
  const logRef = useRef(null);
  const ctx = { installed };

  useEffect(() => {
    const el = logRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [log]);

  useEffect(() => {
    const onKey = (e) => {
      if (e.key === 'Escape' && phase !== 'running') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, phase]);

  async function submit(e) {
    e.preventDefault();
    const problem = validateForm(action, values, ctx);
    if (problem) {
      setError(problem);
      return;
    }
    setError('');
    setPhase('running');
    setLog('');
    try {
      const code = await runAction(server.id, actionId, buildAnswers(action, values, ctx), (text) =>
        setLog((prev) => prev + stripAnsi(text)),
      );
      setExitCode(code);
    } catch (err) {
      setLog((prev) => `${prev}\n[ERR ] ${err.message}\n`);
      setExitCode(-1);
    }
    setPhase('done');
    onFinished?.();
  }

  function requestClose() {
    if (phase === 'running' && !window.confirm('操作仍在服务器上执行，关闭窗口不会中断它。确定关闭吗？')) return;
    onClose();
  }

  const success = phase === 'done' && exitCode === 0;
  // 按终端语义处理 \r：同一行里只保留最后一次刷新的内容（例如下载进度）。
  const lines = log.split('\n').map((line) => line.split('\r').filter(Boolean).pop() ?? '');
  const lastError = [...lines].reverse().find((l) => /^\[ERR \]/.test(l));

  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && phase === 'form' && onClose()}>
      <div className={`modal action-modal ${action.danger ? 'danger' : ''}`} role="dialog" aria-modal="true" aria-label={action.title}>
        <div className="modal-head">
          <div>
            <h2>{action.title}</h2>
            <p className="action-target mono">{server.name}</p>
          </div>
          <button type="button" className="icon-btn ghost" onClick={requestClose} aria-label="关闭">
            <Icon name="close" />
          </button>
        </div>

        {phase === 'form' && (
          <form className="action-form" onSubmit={submit}>
            <p className="action-desc">{action.description}</p>
            {action.warnWhenInstalled && installed && (
              <div className="callout callout-warn">
                <Icon name="shield" size={16} />
                <span>{action.warnWhenInstalled}</span>
              </div>
            )}
            {visibleFields(action, values, ctx).length > 0 && (
              <div className="form-grid">
                {visibleFields(action, values, ctx).map((field) => (
                  <Field
                    key={field.key}
                    field={field}
                    value={values[field.key]}
                    onChange={(v) => setValues((prev) => ({ ...prev, [field.key]: v }))}
                  />
                ))}
              </div>
            )}
            {error && <div className="banner error">{error}</div>}
            <div className="modal-actions">
              <button type="button" className="btn" onClick={onClose}>
                取消
              </button>
              <button type="submit" className={`btn ${action.danger ? 'danger-solid' : 'primary'}`}>
                {action.submit}
              </button>
            </div>
          </form>
        )}

        {phase !== 'form' && (
          <>
            <div className={`run-status run-${phase === 'running' ? 'running' : success ? 'ok' : 'fail'}`}>
              {phase === 'running' && <span className="loader" />}
              {phase === 'done' && <Icon name={success ? 'check' : 'close'} size={18} />}
              <div>
                <strong>
                  {phase === 'running' ? `正在${action.submit}…` : success ? `${action.submit}完成` : `${action.submit}失败`}
                </strong>
                <p>
                  {phase === 'running'
                    ? '服务器上的脚本正在执行，下载二进制可能需要一两分钟。'
                    : success
                      ? '服务状态已刷新。'
                      : friendlyError(lastError, action) || `脚本退出码 ${exitCode}，请查看下面的日志。`}
                </p>
              </div>
            </div>
            <div className="run-log" ref={logRef} aria-live="polite">
              {lines.map((line, i) => (
                // eslint-disable-next-line react/no-array-index-key
                <div key={i} className={`log-line ${lineTone(line)}`}>
                  {line || ' '}
                </div>
              ))}
            </div>
            {phase === 'done' && (
              <div className="modal-actions">
                {!success && (
                  <button type="button" className="btn" onClick={() => setPhase('form')}>
                    修改后重试
                  </button>
                )}
                {success && action.params && (
                  <button type="button" className="btn" onClick={() => onShowParams(action.params)}>
                    <Icon name="key" size={14} />
                    查看连接参数
                  </button>
                )}
                <button type="button" className="btn primary" onClick={onClose}>
                  完成
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
