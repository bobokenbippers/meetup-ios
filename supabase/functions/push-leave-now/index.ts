import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered by pg_cron every 5 minutes.
// Sends "Time to head out" push to accepted participants whose meetup
// has target_arrival_at in the next 25–35 minutes.
serve(async (_req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const now = Date.now()
    const windowStart = new Date(now + 25 * 60 * 1000).toISOString()
    const windowEnd = new Date(now + 35 * 60 * 1000).toISOString()

    const { data: meetups, error: mErr } = await supabase
      .from("meetups")
      .select("id, destination_name")
      .gte("target_arrival_at", windowStart)
      .lte("target_arrival_at", windowEnd)

    if (mErr) {
      console.error("push-leave-now meetup query error:", mErr)
      return new Response("error", { status: 200 })
    }
    if (!meetups?.length) return new Response("no meetups", { status: 200 })

    for (const meetup of meetups) {
      const { data: participants } = await supabase
        .from("meetup_participants")
        .select("user_id")
        .eq("meetup_id", meetup.id)
        .in("status", ["yes", "accepted"])

      if (!participants?.length) continue

      const userIds = participants.map((p: any) => p.user_id)

      const { data: tokenRows } = await supabase
        .from("device_tokens")
        .select("token")
        .in("user_id", userIds)
        .eq("platform", "ios")

      if (!tokenRows?.length) continue

      const destName = meetup.destination_name ?? "your destination"

      await Promise.all(
        tokenRows.map((row: any) =>
          sendPush(row.token, {
            title: "Time to head out 🚗",
            body: `Your meetup at ${destName} starts in 30 minutes`,
            event: "leave_now",
            meetupId: meetup.id,
          }),
        ),
      )
    }

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-leave-now error:", err)
    return new Response("error", { status: 200 })
  }
})
