import { FitAddon } from '@xterm/addon-fit';
import { Terminal } from '@xterm/xterm';
import { useEffect, useRef, useState } from 'react';
import { terminalUrl } from '../api.js';
import Icon from './Icon.jsx';

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
      fontFamily: '"Geist Mono Variable", ui-monospace, SFMono-Regular, Menlo, monospace',
      fontSize: 13,
      lineHeight: 1.25,
      scrollback: 5000,
      theme: {
        background: '#101828',
        foreground: '#dbe4f3',
        cursor: '#5eead4',
        selectionBackground: '#3d5afe55',
        green: '#34d399',
        brightGreen: '#6ee7b7',
        blue: '#7c9cff',
        brightBlue: '#a5b8ff',
        yellow: '#fbbf24',
        red: '#f87171',
      },
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

  const stateText = {
    idle: '未连接',
    connecting: '正在连接',
    open: mode === 'menu' ? '管理菜单' : 'Root Shell',
    closed: '会话已结束',
  }[state];

  return (
    <div className="terminal-panel">
      <div className="terminal-window">
        <div className="terminal-bar">
          <div className="segmented" role="group" aria-label="终端模式">
            <button type="button" className={mode === 'menu' && active ? 'on' : ''} onClick={() => connect('menu')}>
              <Icon name="logs" size={14} />
              管理菜单
            </button>
            <button type="button" className={mode === 'shell' && active ? 'on' : ''} onClick={() => connect('shell')}>
              <Icon name="terminal" size={14} />
              Root Shell
            </button>
          </div>
          <span className={`term-state term-${state}`}>
            <span className="term-led" />
            {stateText}
            <span className="term-host mono">{server.host}</span>
          </span>
          {active && (
            <button type="button" className="term-close" onClick={disconnect}>
              断开
            </button>
          )}
        </div>
        <div className="terminal-host" ref={hostRef} />
      </div>
      <p className="hint">窗口大小改变后，重新连接即可让终端尺寸跟上。</p>
    </div>
  );
}
