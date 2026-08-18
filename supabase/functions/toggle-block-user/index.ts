import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { userId, isBlocked } = await req.json()
    const supabaseAdmin = createClient(
      Deno.env.get('URL')!,
      Deno.env.get('SERVICE_ROLE_KEY')!
    )
    const { error } = await supabaseAdmin
      .from('profiles')
      .update({ is_blocked: isBlocked })
      .eq('id', userId)
    if (error) throw error
    return new Response(JSON.stringify({ success: true }), { status: 200 })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
})