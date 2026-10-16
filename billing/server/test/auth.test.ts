import { generateKeyPair, SignJWT } from 'jose';
import { beforeAll, describe, expect, it } from 'vitest';
import { createClerkAuthenticator } from '../src/auth.js';

let pair: { publicKey: CryptoKey; privateKey: CryptoKey };
let other: { publicKey: CryptoKey; privateKey: CryptoKey };

beforeAll(async () => {
  pair = await generateKeyPair('RS256');
  other = await generateKeyPair('RS256');
});

const ISS = 'https://clerk.example.com';
const sign = (claims: Record<string, unknown>, key: CryptoKey, exp: string | number = '5m') =>
  new SignJWT(claims).setProtectedHeader({ alg: 'RS256', kid: 'k1' }).setIssuer(ISS).setSubject('user_123').setIssuedAt().setExpirationTime(exp).sign(key);
const request = (token?: string) => new Request('https://x.test/', { headers: token ? { authorization: `Bearer ${token}` } : {} });
const auth = (opts: { issuer?: string | null; authorizedParties?: string[] } = {}) =>
  createClerkAuthenticator({ keys: async () => pair.publicKey, issuer: ISS, ...opts });

describe('createClerkAuthenticator', () => {
  it('accepts a valid token and returns the Clerk user id', async () => {
    expect(await auth()(request(await sign({}, pair.privateKey)))).toEqual({ userId: 'user_123', email: null });
  });

  it('passes on the email claim when the session token carries a sane one, and ignores junk', async () => {
    expect(await auth()(request(await sign({ email: 'robin@example.com' }, pair.privateKey)))).toEqual({ userId: 'user_123', email: 'robin@example.com' });
    for (const junk of ['not an email', 42, 'a@b', 'x'.repeat(300) + '@example.com', null]) {
      expect((await auth()(request(await sign({ email: junk }, pair.privateKey)))).email).toBeNull();
    }
  });

  it.each([
    ['no header', () => request()],
    ['not a bearer header', () => new Request('https://x.test/', { headers: { authorization: 'Basic abc' } })],
    ['garbage token', () => request('not.a.jwt')],
  ])('rejects %s', async (_name, make) => {
    await expect(auth()(make())).rejects.toMatchObject({ code: 'unauthorized', status: 401 });
  });

  it('rejects a token signed by another key', async () => {
    await expect(auth()(request(await sign({}, other.privateKey)))).rejects.toMatchObject({ status: 401 });
  });

  it('rejects an expired token', async () => {
    await expect(auth()(request(await sign({}, pair.privateKey, Math.floor(Date.now() / 1000) - 60)))).rejects.toMatchObject({ status: 401 });
  });

  it('rejects a token from another issuer', async () => {
    await expect(auth({ issuer: 'https://someone-else.example.com' })(request(await sign({}, pair.privateKey)))).rejects.toMatchObject({ status: 401 });
  });

  it('checks azp only when the token carries one', async () => {
    const strict = auth({ authorizedParties: ['https://app.example.com'] });
    await expect(strict(request(await sign({ azp: 'https://evil.example.com' }, pair.privateKey)))).rejects.toMatchObject({ status: 401 });
    expect(await strict(request(await sign({ azp: 'https://app.example.com' }, pair.privateKey)))).toEqual({ userId: 'user_123', email: null });
    expect(await strict(request(await sign({}, pair.privateKey)))).toEqual({ userId: 'user_123', email: null }); // native token: no azp
  });

  it('rejects an HS256 token (algorithm confusion)', async () => {
    const hs = await new SignJWT({}).setProtectedHeader({ alg: 'HS256' }).setSubject('user_123').setIssuer(ISS).setExpirationTime('5m').sign(new TextEncoder().encode('secret'));
    await expect(auth()(request(hs))).rejects.toMatchObject({ status: 401 });
  });
});
