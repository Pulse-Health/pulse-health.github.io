-- Pulse billing: Stripe customers, subscriptions and processed webhook events.
-- Plain PostgreSQL (tested on 16 and 17). Keyed by the Clerk user id (the JWT `sub`), which is text like 'user_2abc...'.
-- Apply with `npm run migrate` or with whatever migration tool the host service uses; the statements are idempotent.

create table if not exists billing_customers (
    user_id            text primary key,
    stripe_customer_id text not null unique,
    created_at         timestamptz not null default now()
);

create table if not exists billing_subscriptions (
    stripe_subscription_id text primary key,
    user_id                text not null references billing_customers (user_id) on delete cascade,
    stripe_customer_id     text not null,
    status                 text not null,
    plan_id                text,                       -- price lookup_key, e.g. premium_monthly
    price_id               text not null,
    currency               text,
    unit_amount            bigint,
    current_period_end     timestamptz,
    cancel_at_period_end   boolean not null default false,
    canceled_at            timestamptz,
    trial_end              timestamptz,
    -- False while a trial exists but no payment method was collected yet (does not unlock Premium).
    payment_method_attached boolean not null default true,
    stripe_created_at      timestamptz not null,
    -- When this state was read from Stripe. Writes with an older value are discarded (see upsertSubscription).
    fetched_at             timestamptz not null,
    updated_at             timestamptz not null default now()
);

create index if not exists billing_subscriptions_user_idx on billing_subscriptions (user_id);
create index if not exists billing_subscriptions_customer_idx on billing_subscriptions (stripe_customer_id);

-- One row per Stripe event we have started to process. `processed_at` null = not finished (failed or in flight).
create table if not exists billing_webhook_events (
    stripe_event_id text primary key,
    event_type      text not null,
    received_at     timestamptz not null default now(),
    locked_until    timestamptz,
    attempts        integer not null default 0,
    processed_at    timestamptz,
    last_error      text
);
