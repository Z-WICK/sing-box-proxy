export function serverHealth(status) {
  if (!status || (status.loading && !status.data && !status.error)) return 'unknown';
  if (status.error) return 'down';
  const services = status.data?.services || [];
  if (services.some((s) => s.active !== 'active' && s.enabled === 'enabled')) return 'warn';
  return 'up';
}

const LABELS = { unknown: '检测中', down: '无法连接', warn: '有服务未运行', up: '正常' };

export default function StatusDot({ status }) {
  const health = serverHealth(status);
  return <span className={`dot dot-${health}`} title={LABELS[health]} aria-label={LABELS[health]} />;
}
