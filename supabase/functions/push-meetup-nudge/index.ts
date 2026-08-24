import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered manually by the host via the nudge_meetup_participant RPC.
// Payload: { meetupId: string, userId: string }
serve(async (req) => {
  try {
    const { meetupId, userId } = await req.json()
    if (!meetupId || !userId) return new Response("missing fields", { status: 200 })

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const [{ data: meetup }, { data: invitee }] = await Promise.all([
      supabase
        .from("meetups")
        .select("host_id, destination_name")
        .eq("id", meetupId)
        .single(),
      supabase
        .from("profiles")
        .select("apns_token")
        .eq("id", userId)
        .single(),
    ])

    if (!meetup) return new Response("meetup not found", { status: 200 })
    if (!invitee?.apns_token) return new Response("no token", { status: 200 })

    const { data: host } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", meetup.host_id)
      .single()

    const hostName = host?.display_name ?? "Someone"
    const meetupName = meetup.destination_name ?? "your meetup"

    await sendPush(invitee.apns_token, {
      title: `${hostName} nudged you`,
      body: `Please respond to ${meetupName}`,
      event: "meetup_nudge",
      meetupId,
    })

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-meetup-nudge error:", err)
    return new Response("error", { status: 200 })
  }
})
