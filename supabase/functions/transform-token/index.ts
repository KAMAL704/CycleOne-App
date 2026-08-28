import CryptoJS from 'npm:crypto-js@4.2.0';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const tokenLength = 40;
const aesKeyLength = 16;

type Action = 'unlock' | 'lock';

function response(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}

function bytesToWordArray(bytes: Uint8Array) {
  const words: number[] = [];
  for (let index = 0; index < bytes.length; index += 1) {
    words[index >>> 2] = (words[index >>> 2] ?? 0) | (bytes[index] << (24 - (index % 4) * 8));
  }
  return CryptoJS.lib.WordArray.create(words, bytes.length);
}

function wordArrayToBytes(wordArray: CryptoJS.lib.WordArray) {
  const bytes = new Uint8Array(wordArray.sigBytes);
  for (let i = 0; i < wordArray.sigBytes; i += 1) {
    bytes[i] = (wordArray.words[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xff;
  }
  return bytes;
}

function normalizeMac(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const compact = value.replace(/[^0-9a-f]/gi, '').toUpperCase();
  if (!/^[0-9A-F]{12}$/.test(compact)) return null;
  return compact.match(/.{2}/g)!.join(':');
}

function macBytes(mac: string) {
  return Uint8Array.from(mac.split(':').map((part) => Number.parseInt(part, 16)));
}

function equal(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

function decryptBlock(ciphertext: Uint8Array, iv: Uint8Array, key: Uint8Array) {
  const decrypted = CryptoJS.AES.decrypt(
    CryptoJS.lib.CipherParams.create({ ciphertext: bytesToWordArray(ciphertext) }),
    bytesToWordArray(key),
    { iv: bytesToWordArray(iv), mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.NoPadding },
  );
  return wordArrayToBytes(decrypted);
}

function encryptBlock(plaintext: Uint8Array, iv: Uint8Array, key: Uint8Array) {
  const encrypted = CryptoJS.AES.encrypt(bytesToWordArray(plaintext), bytesToWordArray(key), {
    iv: bytesToWordArray(iv), mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.NoPadding,
  });
  return wordArrayToBytes(encrypted.ciphertext);
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return response({ error: 'Method not allowed' }, 405);
  try {
    const authorization = request.headers.get('Authorization');
    if (!authorization) return response({ error: 'Authentication required' }, 401);
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: userError } = await callerClient.auth.getUser();
    if (userError || !user) return response({ error: 'Authentication required' }, 401);

    const body = await request.json();
    const action: Action | null = body.action === 'unlock' || body.action === 'lock' ? body.action : null;
    const expectedMac = normalizeMac(body.mac);
    const cycleId = typeof body.cycleId === 'string' ? body.cycleId : null;
    const standId = typeof body.standId === 'string' ? body.standId : null;
    if (!action || !expectedMac || !cycleId || !standId || !Array.isArray(body.token) || body.token.length !== tokenLength ||
      body.token.some((byte: unknown) => !Number.isInteger(byte) || byte < 0 || byte > 255)) {
      return response({ error: 'Invalid token request' }, 400);
    }
    const keyHex = Deno.env.get('CYCLEONE_AES_KEY_HEX');
    if (!keyHex || !/^[0-9a-f]{32}$/i.test(keyHex)) return response({ error: 'Lock service is not configured' }, 503);
    const key = Uint8Array.from(keyHex.match(/.{2}/g)!.map((value) => Number.parseInt(value, 16)));
    if (key.length !== aesKeyLength) return response({ error: 'Lock service is not configured' }, 503);
    const token = Uint8Array.from(body.token);
    const nonce = token.slice(0, 8);
    const iv = token.slice(8, 24);
    const plaintext = decryptBlock(token.slice(24, 40), iv, key);
    if (plaintext.length !== 16 || !equal(nonce, plaintext.slice(0, 8))) return response({ error: 'Invalid lock nonce' }, 401);
    if (!equal(macBytes(expectedMac), plaintext.slice(9, 15))) return response({ error: 'Wrong ESP selected' }, 401);
    const currentState = plaintext[8];
    if (currentState !== 0 && currentState !== 1) return response({ error: 'Invalid lock state' }, 400);
    const desiredState = action === 'unlock' ? 1 : 0;
    if (currentState === desiredState) return response({ error: 'Lock already has requested state' }, 409);

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: profile } = await admin.from('profiles').select('status').eq('id', user.id).maybeSingle();
    if (profile?.status !== 'active') return response({ error: 'Account is not active' }, 403);
    const { data: stand } = await admin.from('stands').select('id, esp_mac, status, capacity').eq('id', standId).maybeSingle();
    if (!stand || stand.status !== 'active' || normalizeMac(stand.esp_mac) !== expectedMac) return response({ error: 'Stand authorization failed' }, 403);

    if (action === 'unlock') {
      const { data: activeRide } = await admin.from('rides').select('id').eq('user_id', user.id).eq('status', 'active').maybeSingle();
      const { data: cycle } = await admin.from('cycles').select('id, physical_state').eq('id', cycleId).eq('stand_id', standId).eq('status', 'available').maybeSingle();
      if (activeRide || !cycle || cycle.physical_state === 'absent') return response({ error: 'Cycle unlock is not authorized' }, 403);
    } else {
      const { data: activeRide } = await admin.from('rides').select('id').eq('user_id', user.id).eq('cycle_id', cycleId).eq('status', 'active').maybeSingle();
      if (!activeRide) return response({ error: 'Cycle return is not authorized' }, 403);
      const { data: parkedCycles, error: capacityError } = await admin
        .from('cycles')
        .select('id')
        .eq('stand_id', standId)
        .in('status', ['available', 'maintenance', 'disabled'])
        .neq('physical_state', 'absent');
      if (capacityError) return response({ error: 'Stand capacity could not be verified' }, 503);
      if ((parkedCycles?.length ?? 0) >= Number(stand.capacity ?? 0)) {
        return response({ error: 'Destination stand is full' }, 409);
      }
    }

    const transformedPayload = Uint8Array.from(plaintext);
    transformedPayload[8] = desiredState;
    const newIv = crypto.getRandomValues(new Uint8Array(16));
    const encrypted = encryptBlock(transformedPayload, newIv, key);
    if (encrypted.length !== 16) return response({ error: 'Token encryption failed' }, 500);
    return response({ success: true, macVerified: true, transformedToken: [...nonce, ...newIv, ...encrypted] });
  } catch (error) {
    // Never log token bytes or AES material.
    console.error('[AES] transform-token failed', error instanceof Error ? error.message : 'unknown');
    return response({ error: 'Token transformation failed' }, 500);
  }
});
