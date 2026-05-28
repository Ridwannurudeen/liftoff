import { formatUnits } from "viem";

/** Format a uint as `<num> dUSD2` (or whatever symbol) with 4 decimal places of detail. */
export function fmtAmount(
  value: bigint | undefined,
  symbol = "",
  decimals = 18,
): string {
  if (value === undefined) return "—";
  const s = formatUnits(value, decimals);
  // Trim to 4 dp for display, preserve full precision in title attribute when callers want it.
  const [whole, frac = ""] = s.split(".");
  const trimmed = frac
    ? `${whole}.${frac.slice(0, 4).replace(/0+$/, "")}`
    : whole;
  const cleaned = trimmed.endsWith(".") ? trimmed.slice(0, -1) : trimmed;
  return symbol ? `${cleaned} ${symbol}` : cleaned;
}

export function fmtTimestamp(ts: bigint | undefined): string {
  if (ts === undefined) return "—";
  const ms = Number(ts) * 1000;
  if (!Number.isFinite(ms)) return String(ts);
  return new Date(ms).toISOString().replace("T", " ").slice(0, 19) + " UTC";
}

export function fmtCountdown(target: bigint, now: bigint): string {
  const remaining = Number(target - now);
  if (remaining <= 0) return "0s";
  const m = Math.floor(remaining / 60);
  const s = remaining % 60;
  if (m < 60) return `${m}m ${s}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}
