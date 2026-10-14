const whole = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
const cents = new Intl.NumberFormat('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/**
 * Formats ngwee as kwacha: 16299 -> "K162.99", 50000 -> "K500". Whole amounts
 * drop the decimals, which is how prices are usually shown.
 */
export function kwacha(ngwee: number): string {
  const sign = ngwee < 0 ? '-' : '';
  const abs = Math.abs(ngwee);
  const text = abs % 100 === 0 ? whole.format(abs / 100) : cents.format(abs / 100);
  return `${sign}K${text}`;
}
