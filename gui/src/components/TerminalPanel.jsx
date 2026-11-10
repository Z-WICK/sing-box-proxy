import { FitAddon } from '@xterm/addon-fit';
import { Terminal } from '@xterm/xterm';
import { useEffect, useRef, useState } from 'react';
import { terminalUrl } from '../api.js';

export default function TerminalPanel({ server, visible, onSessionEnd }) {
  const hostRef = useRef(null);
  const termRef = useRef(null);
  const fitRef = useRef(null);
  const wsRef = useRef(null);
  const [state, setState] = useState('idle'); // idle | connecting | open | closed
  const [mode, setMode] = useState('menu');

  useEffect(() => {
    const term = new Terminal({
      cursorBlink: true,
      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
      fontSize: 13,
      scrollback: 5000,
      theme: { background: '#0d1117', foreground: '#e6edf3', cursor: '#7ee787' },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(hostRef.current);
    term.writeln('选择「管理菜单」运行 sing-box-proxy 交互菜单（安装、配置向导、卸载等），');
    term.writeln('或选择「Root Shell」直接进入服务器命令行。');
    termRef.current = term;
    fitRef.current = fit;

    const onResize = () => {
      try {
        fit.fit();
      } catch {
        // 容器隐藏时 fit 会失败，忽略
      }
    };
    window.addEventListener('resize', onResize);
    const disposable = term.onData((data) => {
      const ws = wsRef.current;
      if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'input', data }));
    });

    return () => {
      window.removeEventListener('resize', onResize);
      disposable.dispose();
      wsRef.current?.close();
      term.dispose();
    };
  }, []);

  useEffect(() => {
    if (visible) {
      requestAnimationFrame(() => {
        try {
          fitRef.current?.fit();
        } catch {
          // ignore
        }
        termRef.current?.focus();
      });
    }
  }, [visible]);

  function connect(nextMode) {
    const term = termRef.current;
    wsRef.current?.close();
    try {
      fitRef.current.fit();
    } catch {
      // ignore
    }
    term.reset();
    setMode(nextMode);
    setState('connecting');

    const ws = new WebSocket(terminalUrl(server.id, nextMode, term.cols, term.rows));
    ws.binaryType = 'arraybuffer';
    wsRef.current = ws;
    ws.onopen = () => {
      setState('open');
      term.focus();
    };
    ws.onmessage = (event) => {
      term.write(typeof event.data === 'string' ? event.data : new Uint8Array(event.data));
    };
    ws.onclose = (event) => {
      if (wsRef.current !== ws) return;
      setState('closed');
      if (event.code !== 1000 && event.code !== 1005) {
        term.writeln(`\r\n[连接已断开${event.reason ? `：${event.reason}` : ''}]`);
      }
      onSessionEnd?.();
    };
    ws.onerror = () => {
      term.writeln('\r\n[无法建立终端连接，请检查控制台进程是否仍在运行]');
    };
  }

  function disconnect() {
    wsRef.current?.close();
  }

  const active = state === 'open' || state === 'connecting';

  return (
    <div className="terminal-panel">
      <div className="terminal-toolbar">
        <button type="button" className={`btn small ${mode === 'menu' && active ? 'primary' : ''}`} onClick={() => connect('menu')}>
          管理菜单
        </button>
        <button type="button" className={`btn small ${mode === 'shell' && active ? 'primary' : ''}`} onClick={() => connect('shell')}>
          Root Shell
        </button>
        {active && (
          <button type="button" className="btn small danger-ghost" onClick={disconnect}>
            断开
          </button>
        )}
        <span className="muted small">
          {state === 'connecting' && '连接中…'}
          {state === 'open' && '已连接 · 调整窗口大小后请重新连接以同步终端尺寸'}
          {state === 'closed' && '会话已结束'}
        </span>
      </div>
      <div className="terminal-host" ref={hostRef} />
    </div>
  );
}
