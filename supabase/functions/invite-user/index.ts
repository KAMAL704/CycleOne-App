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
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    const password = typeof body.password === 'string' ? body.password : '';
    if (!email || password.length < 8) return json({ error: 'A valid email and password of at least 8 characters are required' }, 400);
    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: false, user_metadata: { name: body.name?.toString() ?? '', phone: body.phone?.toString() ?? '', registration_id: body.registrationId?.toString() ?? '' } });
    if (error || !data.user) return json({ error: error?.message ?? 'User could not be created' }, 400);
    return json({ success: true, userId: data.user.id });
  } catch (error) {
    console.error('[ADMIN] invite-user failed', error instanceof Error ? error.message : 'unknown');
    return json({ error: 'Request failed' }, 500);
  }
});
