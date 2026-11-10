export function serverHealth(status) {
  if (!status || (status.loading && !status.data && !status.error)) return 'unknown';
  if (status.error) return 'down';
  const services = status.data?.services || [];
  if (services.some((s) => s.active !== 'active' && s.enabled === 'enabled')) return 'warn';
  return 'up';
}

export const HEALTH_LABELS = { up: '在线', warn: '有服务未运行', down: '无法连接', unknown: '检测中' };

export default function StatusDot({ status, health: forced }) {
  const health = forced || serverHealth(status);
  return <span className={`dot dot-${health}`} title={HEALTH_LABELS[health]} role="img" aria-label={HEALTH_LABELS[health]} />;
}
