import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// Triggered by pg_cron every 5 minutes.
// Marks meetups as 'completed' when target_arrival_at + 90 min has passed,
// then wipes location data so participants can't see each other's whereabouts.
serve(async (_req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const expiryThreshold = new Date(Date.now() - 90 * 60 * 1000).toISOString()

    const { data: expired, error: fetchErr } = await supabase
      .from("meetups")
      .select("id")
      .eq("status", "active")
      .lt("target_arrival_at", expiryThreshold)

    if (fetchErr) {
      return new Response(JSON.stringify({ error: fetchErr.message }), { status: 500 })
    }

    if (!expired?.length) {
      return new Response(JSON.stringify({ expired: 0 }), { status: 200 })
    }

    const ids = expired.map((m: { id: string }) => m.id)

    const { error: updateErr } = await supabase
      .from("meetups")
      .update({ status: "completed" })
      .in("id", ids)

    if (updateErr) {
      return new Response(JSON.stringify({ error: updateErr.message }), { status: 500 })
    }

    // Wipe location data so participants can't see each other after the event
    await supabase
      .from("meetup_participants")
      .update({ lat: null, lng: null, bearing: null, eta_seconds: null })
      .in("meetup_id", ids)

    console.log(`expire-meetups: marked ${ids.length} meetup(s) as completed, wiped location data`)
    return new Response(JSON.stringify({ expired: ids.length, ids }), { status: 200 })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 })
  }
})
