-- Lets Stripe subscriptions show up in the Pulse app's existing Premium table, public.user_premium_access, which is
-- what the coaching function (hasActivePremium), the iOS onboarding gate and account deletion already use. One row per
-- Stripe subscription: source = 'stripe', external_ref = the subscription id.
--
-- No-op when that table does not exist (standalone billing service). When it does, the service verifies the column
-- at start-up if BILLING_SYNC_PREMIUM_ACCESS is on (the default).
do $$
begin
    if to_regclass('public.user_premium_access') is not null then
        alter table public.user_premium_access add column if not exists external_ref text;
        create unique index if not exists user_premium_access_external_ref_idx
            on public.user_premium_access (source, external_ref) where external_ref is not null;
    end if;
end
$$;
