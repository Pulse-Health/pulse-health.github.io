import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // The PostgreSQL-backed test files share one database and truncate its tables, so files must not run at the same time.
    fileParallelism: false,
    include: ['test/**/*.test.ts'],
  },
});
