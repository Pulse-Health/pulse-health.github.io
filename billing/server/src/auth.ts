import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import { BillingError } from './types.js';

export interface AuthenticatedUser {
  userId: string;
  /**
   * The user's verified primary email, only if the Clerk session token carries it (Clerk dashboard > Sessions > Customize
   * session token: `{ "email": "{{user.primary_email_address}}" }`). Stripe needs it to send receipts and invoices.
   */
  email?: string | null;
}

/** Resolves the caller of a request. Throws `BillingError('unauthorized', 401)` when there is none. */
export type Authenticator = (request: Request) => Promise<AuthenticatedUser>;

export interface ClerkAuthOptions {
  /** Key resolver for the Clerk instance (`createRemoteJWKSet`); injectable for tests. */
  keys: JWTVerifyGetKey;
  /** Expected `iss` (your Clerk Frontend API URL). Strongly recommended. */
  issuer?: string | null;
  /** Allowed `azp` values for tokens that carry the claim (browser origins). Tokens without `azp` (native SDKs) pass. */
  authorizedParties?: string[];
}

export function clerkJwks(jwksUrl: string): JWTVerifyGetKey {
  return createRemoteJWKSet(new URL(jwksUrl), { cooldownDuration: 30_000, cacheMaxAge: 60 * 60 * 1000 });
}

/**
 * Verifies a Clerk session token the way Clerk documents for custom backends: RS256 signature against the instance's
 * JWKS, `exp`/`nbf`, optional issuer, and `azp` against an allow-list. The user id is the `sub` claim.
 */
export function createClerkAuthenticator(options: ClerkAuthOptions): Authenticator {
  return async (request) => {
    const header = request.headers.get('authorization') ?? '';
    const match = /^Bearer\s+(\S+)$/i.exec(header);
    if (!match?.[1]) throw unauthorized();
    try {
      const { payload } = await jwtVerify(match[1], options.keys, {
        algorithms: ['RS256'],
        clockTolerance: 5,
        requiredClaims: ['exp', 'sub'],
        ...(options.issuer ? { issuer: options.issuer } : {}),
      });
      const parties = options.authorizedParties ?? [];
      if (typeof payload.azp === 'string' && parties.length > 0 && !parties.includes(payload.azp)) throw new Error('azp not allowed');
      if (typeof payload.sub !== 'string' || payload.sub.length === 0) throw new Error('no sub');
      return { userId: payload.sub, email: emailClaim(payload.email) };
    } catch {
      throw unauthorized();
    }
  };
}

const emailClaim = (value: unknown): string | null =>
  typeof value === 'string' && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) ? value : null;

const unauthorized = () => new BillingError('unauthorized', 401, 'Sign in again.');
