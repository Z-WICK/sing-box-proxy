import { spawn } from 'node:child_process';
import { REMOTE_SCRIPT, remoteAsRoot, shq, sshArgs } from './ssh.mjs';

export const TERMINAL_MODES = ['menu', 'shell'];

function clampSize(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isInteger(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

/**
 * 通过 `ssh -tt` 在远端分配伪终端并运行管理菜单或 root shell。
 * 本地不需要 node-pty：远端 pty 负责回显和行编辑，本地只转发字节。
 * 局限：连接建立后无法把窗口尺寸变化同步到远端，需要重新连接。
 */
export function attachTerminal(ws, server, { mode, cols, rows }) {
  const width = clampSize(cols, 20, 500, 120);
  const height = clampSize(rows, 5, 200, 32);
  // 经 ControlMaster 复用通道建立的 pty 不会收到终端模式（icrnl 等全关），
  // 导致 xterm 发送的回车 \r 不会被转换成 \n，脚本里的 `read` 永远等不到行尾。
  // 因此先 `stty sane` 恢复标准模式，再设置窗口尺寸。
  const prelude = `stty sane 2>/dev/null; stty cols ${width} rows ${height} 2>/dev/null; `;
  const command = mode === 'shell'
    ? remoteAsRoot('bash -l', { prelude })
    : remoteAsRoot(['bash', REMOTE_SCRIPT, '--agent', 'menu'].map(shq).join(' '), { prelude });

  const child = spawn('ssh', [...sshArgs(server, { tty: true }), command], {
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, TERM: 'xterm-256color' },
  });

  const send = (chunk) => {
    if (ws.readyState === ws.OPEN) ws.send(chunk, { binary: true });
  };
  child.stdout.on('data', send);
  child.stderr.on('data', send);
  child.stdin.on('error', () => {});

  child.on('error', (err) => {
    send(Buffer.from(`\r\n[本地启动 ssh 失败: ${err.message}]\r\n`));
    ws.close(1011, 'ssh spawn failed');
  });
  child.on('close', (code) => {
    send(Buffer.from(`\r\n[会话已结束，退出码 ${code ?? '?'}]\r\n`));
    if (ws.readyState === ws.OPEN) ws.close(1000, 'session ended');
  });

  ws.on('message', (data, isBinary) => {
    if (isBinary) {
      child.stdin.write(data);
      return;
    }
    let msg;
    try {
      msg = JSON.parse(data.toString('utf8'));
    } catch {
      return;
    }
    if (msg?.type === 'input' && typeof msg.data === 'string') {
      child.stdin.write(msg.data);
    }
  });

  ws.on('close', () => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
  });
}
