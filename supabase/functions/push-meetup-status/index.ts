import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered by Postgres: AFTER UPDATE ON meetup_participants
// when status changes to 'accepted', 'declined', or 'arrived'
// meetup_participants has a composite PK (meetup_id, user_id) — no id column.
// Payload: { meetupId: string, userId: string, newStatus: string }
serve(async (req) => {
  try {
    const { meetupId, userId, newStatus } = await req.json()
    if (!["accepted", "declined", "arrived"].includes(newStatus)) {
      return new Response("ignored", { status: 200 })
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const [{ data: meetup }, { data: actor }] = await Promise.all([
      supabase
        .from("meetups")
        .select("destination_name, host_id")
        .eq("id", meetupId)
        .single(),
      supabase
        .from("profiles")
        .select("display_name")
        .eq("id", userId)
        .single(),
    ])

    const actorName = actor?.display_name ?? "Someone"
    const meetupName = meetup?.destination_name ?? "the meetup"

    if (newStatus === "arrived") {
      // Notify host + all accepted participants (excluding the one who arrived)
      const { data: recipients } = await supabase
        .from("meetup_participants")
        .select("user_id, profiles(apns_token)")
        .eq("meetup_id", meetupId)
        .in("status", ["accepted", "invited"])
        .neq("user_id", userId)

      // Also notify host if not already in the list
      const recipientIds = new Set((recipients ?? []).map((r: any) => r.user_id))
      const extraTokens: string[] = []
      if (meetup?.host_id && !recipientIds.has(meetup.host_id)) {
        const { data: hostProfile } = await supabase
          .from("profiles")
          .select("apns_token")
          .eq("id", meetup.host_id)
          .single()
        if (hostProfile?.apns_token) extraTokens.push(hostProfile.apns_token)
      }

      const tokens = [
        ...(recipients ?? [])
          .map((r: any) => r.profiles?.apns_token)
          .filter(Boolean),
        ...extraTokens,
      ]

      await Promise.all(
        tokens.map((token: string) =>
          sendPush(token, {
            title: `${actorName} arrived! 🎉`,
            body: `They made it to ${meetupName}`,
            event: "meetup_arrived",
            meetupId: meetupId,
          }),
        ),
      )
    } else {
      // accepted or declined — notify host only
      const { data: hostProfile } = await supabase
        .from("profiles")
        .select("apns_token")
        .eq("id", meetup?.host_id)
        .single()

      if (!hostProfile?.apns_token) return new Response("no token", { status: 200 })

      const verb = newStatus === "accepted" ? "accepted" : "declined"
      await sendPush(hostProfile.apns_token, {
        title: `${actorName} ${verb}`,
        body: `${actorName} ${verb} your invite to ${meetupName}`,
        event: `meetup_${newStatus}`,
        meetupId: meetupId,
      })
    }

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-meetup-status error:", err)
    return new Response("error", { status: 200 })
  }
})
