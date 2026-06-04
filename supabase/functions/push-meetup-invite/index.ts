import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered by Postgres: AFTER INSERT ON meetup_participants WHERE status = 'invited'
// Payload: { participantId: string }
serve(async (req) => {
  try {
    const { participantId } = await req.json()
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    // Resolve the invite: who was invited, to which meetup, by whom
    const { data: participant, error: pErr } = await supabase
      .from("meetup_participants")
      .select("user_id, meetup_id")
      .eq("id", participantId)
      .single()
    if (pErr || !participant) return new Response("not found", { status: 200 })

    const [{ data: meetup }, { data: invitee }] = await Promise.all([
      supabase
        .from("meetups")
        .select("name, host_id, destination_name")
        .eq("id", participant.meetup_id)
        .single(),
      supabase
        .from("profiles")
        .select("apns_token")
        .eq("id", participant.user_id)
        .single(),
    ])

    if (!invitee?.apns_token) return new Response("no token", { status: 200 })

    // Resolve host display name
    const { data: host } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", meetup?.host_id)
      .single()

    const hostName = host?.display_name ?? "Someone"
    const meetupName = meetup?.name ?? "a meetup"
    const dest = meetup?.destination_name ? ` → ${meetup.destination_name}` : ""

    await sendPush(invitee.apns_token, {
      title: `${hostName} invited you`,
      body: `Join ${meetupName}${dest}`,
      event: "meetup_invite",
      meetupId: participant.meetup_id,
    })

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-meetup-invite error:", err)
    return new Response("error", { status: 200 }) // always 200 so pg_net doesn't retry forever
  }
})
