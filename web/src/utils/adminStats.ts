export function calcShareValue(count: number, total: number): number {
  if (total <= 0 || count <= 0) return 0;
  const clamped = Math.min(100, Math.max(0, (count / total) * 100));
  return Math.round(clamped * 10) / 10;
}

export function formatPercent(value: number): string {
  return Number.isInteger(value) ? `${value.toFixed(0)}%` : `${value.toFixed(1)}%`;
}

export function formatShareText(
  count: number,
  total: number,
  shareTemplate: string,
  zeroFallback: string
): string {
  if (total <= 0) return zeroFallback;
  const percent = formatPercent(calcShareValue(count, total));
  return shareTemplate.replace('{percent}', percent).replace('{total}', String(total));
}

export function formatCompletionProgressText(
  completed: number,
  total: number,
  template: string
): string {
  const percent = formatPercent(calcShareValue(completed, total));
  return template
    .replace('{completed}', String(completed))
    .replace('{total}', String(total))
    .replace('{percent}', percent);
}
