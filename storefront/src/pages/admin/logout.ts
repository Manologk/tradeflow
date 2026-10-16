import type { APIRoute } from 'astro';
import { clearSession } from '../../lib/admin/auth';

export const POST: APIRoute = ({ cookies, redirect }) => {
  clearSession(cookies);
  return redirect('/admin/login', 303);
};
