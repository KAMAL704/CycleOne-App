import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { email, password } = await req.json()
    if (!email || !password) {
      throw new Error('Email and password are required')
    }

    const supabaseAdmin = createClient(
      Deno.env.get('URL')!,
      Deno.env.get('SERVICE_ROLE_KEY')!
    )

    // Create the user in Auth (email confirmed immediately)
    const { data, error } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    })

    if (error) throw error

    // Also create a profile entry
    await supabaseAdmin
      .from('profiles')
      .upsert({
        id: data.user.id,
        email: email,
        branch: '',
        year: '',
        mobile: '',
        is_admin: false,
        is_blocked: false,
      })

    return new Response(JSON.stringify({ success: true, user: data.user }), { status: 200 })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
})