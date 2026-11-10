import qrcode from 'qrcode-generator';
import { useMemo } from 'react';

// qrcode-generator 默认按 Latin-1 处理字符串，先手动编码成 UTF-8 字节串，
// 这样节点名里的中文等字符也能正确扫码。
function toByteString(text) {
  const bytes = new TextEncoder().encode(text);
  let out = '';
  for (const b of bytes) out += String.fromCharCode(b);
  return out;
}

export default function QrCode({ value, size = 168, label }) {
  const { path, count } = useMemo(() => {
    const qr = qrcode(0, 'M');
    qr.addData(toByteString(value), 'Byte');
    qr.make();
    const n = qr.getModuleCount();
    let d = '';
    for (let r = 0; r < n; r += 1) {
      for (let c = 0; c < n; c += 1) {
        if (qr.isDark(r, c)) d += `M${c} ${r}h1v1h-1z`;
      }
    }
    return { path: d, count: n };
  }, [value]);

  const quiet = 2;
  const box = count + quiet * 2;
  return (
    <svg
      className="qr"
      width={size}
      height={size}
      viewBox={`${-quiet} ${-quiet} ${box} ${box}`}
      shapeRendering="crispEdges"
      role="img"
      aria-label={label || '二维码'}
    >
      <rect x={-quiet} y={-quiet} width={box} height={box} fill="#fff" />
      <path d={path} fill="#16213a" />
    </svg>
  );
}
