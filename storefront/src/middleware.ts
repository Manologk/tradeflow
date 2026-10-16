import { defineMiddleware } from 'astro:middleware';
import { clearSession, getAuthBackend, needsRefresh, readSession, writeSession } from './lib/admin/auth';

// Guards the dashboard: every /admin page and /api/admin call needs the shop
// owner to be signed in. The public shop is untouched.

const isAdminPath = (p: string) => p === '/admin' || p.startsWith('/admin/') || p.startsWith('/api/admin/');

export const onRequest = defineMiddleware(async (ctx, next) => {
  const path = ctx.url.pathname;
  if (!isAdminPath(path)) return next();

  const finish = async () => {
    const res = await next();
    // Private pages: never cached, never indexed.
    res.headers.set('Cache-Control', 'no-store');
    res.headers.set('X-Robots-Tag', 'noindex, nofollow');
    return res;
  };
  if (path === '/admin/login') return finish();

  const isApi = path.startsWith('/api/admin/');
  const deny = () => {
    if (isApi) return new Response(JSON.stringify({ error: 'Please sign in again' }), { status: 401 });
    const nextUrl = encodeURIComponent(path + ctx.url.search);
    return ctx.redirect(`/admin/login?next=${nextUrl}`);
  };

  const backend = getAuthBackend();
  let session = readSession(ctx.cookies);
  if (!backend || !session) return deny();

  if (needsRefresh(session)) {
    try {
      session = await backend.refresh(session.refreshToken);
      writeSession(ctx.cookies, session, ctx.url.protocol === 'https:');
    } catch {
      clearSession(ctx.cookies);
      return deny();
    }
  }
  if (!(await backend.isOwner(session.accessToken))) {
    clearSession(ctx.cookies);
    return deny();
  }

  ctx.locals.admin = backend.admin(session.accessToken);
  ctx.locals.adminEmail = session.email;
  return finish();
});
