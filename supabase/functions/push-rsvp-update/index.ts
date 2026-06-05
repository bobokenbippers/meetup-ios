import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// POST { meetupId: string, userId: string, newStatus: string }
// Notifies the meetup host when a participant updates their RSVP.
serve(async (req) => {
  try {
    const { meetupId, userId, newStatus } = await req.json()
    if (!meetupId || !userId || !newStatus) {
      return new Response("missing fields", { status: 400 })
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    // Fetch the meetup to get host_id and destination_name
    const { data: meetup, error: mErr } = await supabase
      .from("meetups")
      .select("host_id, destination_name")
      .eq("id", meetupId)
      .single()
    if (mErr || !meetup) return new Response("meetup not found", { status: 200 })

    // Don't notify if the RSVP-er is the host
    if (meetup.host_id === userId) return new Response("host rsvp, skip", { status: 200 })

    // Get the responding participant's display name
    const { data: respondent } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", userId)
      .single()

    // Get the host's device token
    const { data: tokenRows } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", meetup.host_id)
      .eq("platform", "ios")
      .limit(1)

    if (!tokenRows?.length) return new Response("no host token", { status: 200 })

    const displayName = respondent?.display_name ?? "Someone"
    const meetupName = meetup.destination_name ?? "your meetup"

    const statusLabel =
      newStatus === "yes" ? "Yes"
      : newStatus === "no" ? "No"
      : newStatus === "maybe" ? "Maybe"
      : newStatus

    await sendPush(tokenRows[0].token, {
      title: "RSVP Update",
      body: `${displayName} said ${statusLabel} to ${meetupName}`,
      event: "rsvp_update",
      meetupId,
    })

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-rsvp-update error:", err)
    return new Response("error", { status: 200 })
  }
})
