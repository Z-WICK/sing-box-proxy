// 线性图标集（24×24，描边 1.75），只收录界面实际用到的图标。
const PATHS = {
  refresh: ['M21 12a9 9 0 1 1-2.64-6.36', 'M21 3v6h-6'],
  sync: ['M4 14a8 8 0 0 0 14.9 3', 'M20 10A8 8 0 0 0 5.1 7', 'M4 4v4h4', 'M20 20v-4h-4'],
  edit: ['M4 20h4L19 9a2.83 2.83 0 0 0-4-4L4 16v4Z', 'M13.5 6.5l4 4'],
  trash: ['M4 7h16', 'M10 11v6', 'M14 11v6', 'M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12', 'M9 7V4h6v3'],
  terminal: ['M4 17l6-5-6-5', 'M12 19h8'],
  params: ['M9 4H7a3 3 0 0 0-3 3v10a3 3 0 0 0 3 3h10a3 3 0 0 0 3-3v-2', 'M14 4h6v6', 'M20 4l-9 9'],
  logs: ['M8 6h12', 'M8 12h12', 'M8 18h12', 'M4 6h.01', 'M4 12h.01', 'M4 18h.01'],
  play: ['M7 4.5v15l12.5-7.5L7 4.5Z'],
  stop: ['M7 7h10v10H7z'],
  restart: ['M3 12a9 9 0 1 0 3-6.7', 'M3 4v5h5'],
  plus: ['M12 5v14', 'M5 12h14'],
  search: ['M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14Z', 'M20 20l-4-4'],
  server: ['M4 5h16v6H4z', 'M4 13h16v6H4z', 'M8 8h.01', 'M8 16h.01'],
  grid: ['M4 4h7v7H4z', 'M13 4h7v7h-7z', 'M4 13h7v7H4z', 'M13 13h7v7h-7z'],
  close: ['M6 6l12 12', 'M18 6L6 18'],
  copy: ['M9 9h11v11H9z', 'M5 15H4V4h11v1'],
  check: ['M5 12.5l4.5 4.5L19 7.5'],
  key: ['M15 14a5 5 0 1 0 0-10 5 5 0 0 0 0 10Z', 'M11.5 12.5L4 20', 'M6 18l2 2', 'M8.5 15.5l2 2', 'M16 8h.01'],
  eye: ['M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z', 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z'],
  eyeOff: ['M3 3l18 18', 'M10.6 5.6A9.8 9.8 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-2.9 3.7', 'M6.6 6.6C3.9 8.3 2.5 12 2.5 12S6 18.5 12 18.5c1.6 0 3-.4 4.3-1', 'M9.9 9.9a3 3 0 0 0 4.2 4.2'],
  qr: ['M4 4h6v6H4z', 'M14 4h6v6h-6z', 'M4 14h6v6H4z', 'M14 14h2v2h-2z', 'M18 14h2', 'M14 18h2v2', 'M18 18h2v2h-2z'],
  shield: ['M12 3l8 3v6c0 4.5-3.4 8.2-8 9-4.6-.8-8-4.5-8-9V6l8-3Z', 'M12 8v4', 'M12 15.5h.01'],
  info: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M12 11v5', 'M12 7.5h.01'],
  more: ['M5 12h.01', 'M12 12h.01', 'M19 12h.01'],
  unplug: ['M5 19l3-3', 'M14 5l-3 3', 'M8 10l6 6', 'M10 8l6 6', 'M16 8l3-3'],
};

export default function Icon({ name, size = 16, className = '' }) {
  const paths = PATHS[name] || [];
  return (
    <svg
      className={`icon ${className}`}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths.map((d) => (
        <path key={d} d={d} />
      ))}
    </svg>
  );
}
