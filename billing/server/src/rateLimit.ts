/** Fixed-window limiter, per process. Enough to stop a client loop from hammering Stripe; not a security boundary. */
export class RateLimiter {
  private windows = new Map<string, { start: number; count: number }>();

  constructor(
    private readonly max: number,
    private readonly windowMs: number,
    private readonly clock: () => number = Date.now,
  ) {}

  /** True when the call is allowed. */
  take(key: string): boolean {
    const now = this.clock();
    if (this.windows.size > 10_000) this.prune(now);
    const w = this.windows.get(key);
    if (!w || now - w.start >= this.windowMs) {
      this.windows.set(key, { start: now, count: 1 });
      return true;
    }
    if (w.count >= this.max) return false;
    w.count += 1;
    return true;
  }

  private prune(now: number): void {
    for (const [key, w] of this.windows) if (now - w.start >= this.windowMs) this.windows.delete(key);
  }
}
