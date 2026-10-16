import type { AstroCookies } from 'astro';
import { getSecret } from 'astro:env/server';
import { fixtureAdmin } from '../fixtures';
import { supabaseAdmin } from './supabase';
import { AdminError, type AdminApi } from './types';

// Owner sign-in for the dashboard. Supabase Auth checks the password; the
// tokens live in http-only cookies the page's scripts can't read.

export interface Session {
  accessToken: string;
  refreshToken: string;
  /** Unix seconds. */
  expiresAt: number;
  email: string;
}

export interface AuthBackend {
  signIn(email: string, password: string): Promise<Session>;
  refresh(refreshToken: string): Promise<Session>;
  isOwner(accessToken: string): Promise<boolean>;
  admin(accessToken: string): AdminApi;
}

/** Test-only owner login, available when the site runs on the test catalog. */
export const FIXTURE_OWNER = { email: 'owner@animeyay.test', password: 'otaku-admin' };

function fixtureAuth(): AuthBackend {
  const session = (): Session => ({
    accessToken: 'fixture-owner',
    refreshToken: 'fixture-refresh',
    expiresAt: Math.floor(Date.now() / 1000) + 3600,
    email: FIXTURE_OWNER.email,
  });
  return {
    async signIn(email, password) {
      if (email.trim().toLowerCase() !== FIXTURE_OWNER.email || password !== FIXTURE_OWNER.password) {
        throw new AdminError('Wrong email or password');
      }
      return session();
    },
    refresh: async () => session(),
    isOwner: async (token) => token === 'fixture-owner',
    admin: () => fixtureAdmin(),
  };
}

function emailFromJwt(token: string): string {
  try {
    const payload = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return (JSON.parse(atob(payload)) as { email?: string }).email ?? '';
  } catch {
    return '';
  }
}

function supabaseAuth(url: string, anonKey: string): AuthBackend {
  async function token(grant: 'password' | 'refresh_token', body: unknown): Promise<Session> {
    const res = await fetch(`${url}/auth/v1/token?grant_type=${grant}`, {
      method: 'POST',
      headers: { apikey: anonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      throw new AdminError(res.status === 400 ? 'Wrong email or password' : `Sign-in failed (${res.status})`);
    }
    const t = (await res.json()) as { access_token: string; refresh_token: string; expires_in: number };
    return {
      accessToken: t.access_token,
      refreshToken: t.refresh_token,
      expiresAt: Math.floor(Date.now() / 1000) + t.expires_in,
      email: emailFromJwt(t.access_token),
    };
  }
  return {
    signIn: (email, password) => token('password', { email: email.trim(), password }),
    refresh: (refreshToken) => token('refresh_token', { refresh_token: refreshToken }),
    async isOwner(accessToken) {
      // Row-level security only shows an owner their own row.
      const res = await fetch(`${url}/rest/v1/shop_owners?select=user_id`, {
        headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` },
      });
      return res.ok && ((await res.json()) as unknown[]).length > 0;
    },
    admin: (accessToken) => supabaseAdmin(url, anonKey, accessToken),
  };
}

/** Null until the shop is connected to its database. */
export function getAuthBackend(): AuthBackend | null {
  if (getSecret('SHOP_DATA') === 'fixtures') return fixtureAuth();
  const url = getSecret('SUPABASE_URL');
  const key = getSecret('SUPABASE_ANON_KEY');
  return url && key ? supabaseAuth(url, key) : null;
}

const ACCESS = 'ay_admin_at';
const REFRESH = 'ay_admin_rt';
const EXPIRES = 'ay_admin_exp';

function cookieOptions(secure: boolean, maxAge: number) {
  return { httpOnly: true, secure, sameSite: 'lax' as const, path: '/', maxAge };
}

export function readSession(cookies: AstroCookies): Session | null {
  const accessToken = cookies.get(ACCESS)?.value;
  const refreshToken = cookies.get(REFRESH)?.value;
  if (!refreshToken) return null;
  return {
    accessToken: accessToken ?? '',
    refreshToken,
    expiresAt: Number(cookies.get(EXPIRES)?.value ?? 0),
    email: accessToken ? emailFromJwt(accessToken) : '',
  };
}

export function writeSession(cookies: AstroCookies, s: Session, secure: boolean) {
  const accessAge = Math.max(60, s.expiresAt - Math.floor(Date.now() / 1000));
  cookies.set(ACCESS, s.accessToken, cookieOptions(secure, accessAge));
  cookies.set(EXPIRES, String(s.expiresAt), cookieOptions(secure, accessAge));
  // Stay signed in on this device for 30 days of inactivity.
  cookies.set(REFRESH, s.refreshToken, cookieOptions(secure, 60 * 60 * 24 * 30));
}

export function clearSession(cookies: AstroCookies) {
  for (const name of [ACCESS, REFRESH, EXPIRES]) cookies.delete(name, { path: '/' });
}

/** True when the access token is missing or expires within a minute. */
export const needsRefresh = (s: Session) => !s.accessToken || s.expiresAt - 60 < Date.now() / 1000;
