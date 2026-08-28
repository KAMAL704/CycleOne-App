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
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: 'Authentication required' }, 401);
    const admin = createClient(url, service);
    const { data: profile } = await admin.from('profiles').select('role, status').eq('id', user.id).maybeSingle();
    if (profile?.role !== 'admin' || profile.status !== 'active') return json({ error: 'Administrator access required' }, 403);
    const body = await request.json();
    const userId = typeof body.userId === 'string' ? body.userId : null;
    const status = body.status === 'active' || body.status === 'disabled' ? body.status : (body.isBlocked === true ? 'disabled' : body.isBlocked === false ? 'active' : null);
    if (!userId || !status) return json({ error: 'userId and status are required' }, 400);
    if (userId === user.id) return json({ error: 'You cannot disable your own account' }, 400);
    const { error } = await admin.from('profiles').update({ status }).eq('id', userId);
    if (error) return json({ error: error.message }, 400);
    return json({ success: true, status });
  } catch (error) {
    console.error('[ADMIN] toggle-block-user failed', error instanceof Error ? error.message : 'unknown');
    return json({ error: 'Request failed' }, 500);
  }
});
