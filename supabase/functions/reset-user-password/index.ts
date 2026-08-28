import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const headers = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' };
const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), { status, headers });

serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  try {
    const authorization = request.headers.get('Authorization');
    if (!authorization) return json({ error: 'Authentication required' }, 401);
    const url = Deno.env.get('SUPABASE_URL')!;
    const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: 'Authentication required' }, 401);
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: profile } = await admin.from('profiles').select('role, status').eq('id', user.id).maybeSingle();
    if (profile?.role !== 'admin' || profile.status !== 'active') return json({ error: 'Administrator access required' }, 403);
    const body = await request.json();
    const userId = typeof body.userId === 'string' ? body.userId : null;
    const password = typeof body.newPassword === 'string' ? body.newPassword : '';
    if (!userId || password.length < 8) return json({ error: 'userId and a password of at least 8 characters are required' }, 400);
    const { error } = await admin.auth.admin.updateUserById(userId, { password });
    if (error) return json({ error: error.message }, 400);
    return json({ success: true });
  } catch (error) {
    console.error('[ADMIN] reset-user-password failed', error instanceof Error ? error.message : 'unknown');
    return json({ error: 'Request failed' }, 500);
  }
});
