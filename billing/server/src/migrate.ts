import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import pg from 'pg';

// Minimal migration runner so the billing service can be deployed on its own. If the host service has its own
// migration tool, copy migrations/*.sql into it instead; the statements are idempotent.

export async function migrate(databaseUrl: string, dir = defaultDir()): Promise<string[]> {
  const pool = new pg.Pool({ connectionString: databaseUrl, max: 1 });
  const applied: string[] = [];
  try {
    await pool.query('create table if not exists billing_migrations (name text primary key, applied_at timestamptz not null default now())');
    const done = new Set((await pool.query<{ name: string }>('select name from billing_migrations')).rows.map((r) => r.name));
    const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
    for (const file of files) {
      if (done.has(file)) continue;
      const sql = await readFile(path.join(dir, file), 'utf8');
      const client = await pool.connect();
      try {
        await client.query('begin');
        await client.query(sql);
        await client.query('insert into billing_migrations (name) values ($1)', [file]);
        await client.query('commit');
        applied.push(file);
      } catch (error) {
        await client.query('rollback');
        throw error;
      } finally {
        client.release();
      }
    }
  } finally {
    await pool.end();
  }
  return applied;
}

function defaultDir(): string {
  // dist/migrate.js -> ../migrations ; src/migrate.ts (tsx) -> ../migrations
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('DATABASE_URL is required');
    process.exit(1);
  }
  migrate(url).then(
    (applied) => console.log(applied.length ? `applied: ${applied.join(', ')}` : 'up to date'),
    (error) => {
      console.error(error instanceof Error ? error.message : error);
      process.exit(1);
    },
  );
}
