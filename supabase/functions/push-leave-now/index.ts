import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered by pg_cron every 5 minutes.
// Sends "Leave now" push to accepted participants whose predicted arrival time
// (now + current_eta_seconds) puts them at their depart window for target_arrival_at.
// Falls back to a flat 30-minute window for participants without a stored ETA.
serve(async (_req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const now = Date.now()
    // Only consider meetups with target_arrival_at in the next 2 hours
    const windowEnd = new Date(now + 2 * 60 * 60 * 1000).toISOString()

    const { data: meetups, error: mErr } = await supabase
      .from("meetups")
      .select("id, destination_name, target_arrival_at, parking_buffer_min")
      .eq("status", "active")
      .not("target_arrival_at", "is", null)
      .lte("target_arrival_at", windowEnd)

    if (mErr) {
      console.error("push-leave-now meetup query error:", mErr)
      return new Response("error", { status: 200 })
    }
    if (!meetups?.length) return new Response("no meetups", { status: 200 })

    for (const meetup of meetups) {
      const targetMs = new Date(meetup.target_arrival_at).getTime()
      const parkingBufferMin = meetup.parking_buffer_min ?? 0

      // Fetch accepted participants with their ETA, location recency, and APNs token
      const { data: participants } = await supabase
        .from("meetup_participants")
        .select("user_id, current_eta_seconds, last_seen_at, profiles(apns_token)")
        .eq("meetup_id", meetup.id)
        .eq("status", "accepted")

      if (!participants?.length) continue

      for (const p of participants) {
        const profile = (p as any).profiles
        if (!profile?.apns_token) continue

        // Skip participants who are actively moving (last_seen_at within 10 min)
        const lastSeen = p.last_seen_at ? new Date(p.last_seen_at).getTime() : 0
        const minutesSinceLastUpdate = (now - lastSeen) / (60 * 1000)
        if (lastSeen > 0 && minutesSinceLastUpdate < 10) continue

        const minutesToTarget = (targetMs - now) / (60 * 1000)

        // Skip if meetup has already passed
        if (minutesToTarget < 0) continue

        let shouldNotify = false
        const destName = meetup.destination_name ?? "your meetup"

        if (p.current_eta_seconds != null) {
          // ETA-based: depart time = target - ETA - parking_buffer
          // Fire when depart time is 0–5 minutes in the future
          const etaMin = p.current_eta_seconds / 60
          const departInMin = minutesToTarget - etaMin - parkingBufferMin
          if (departInMin >= 0 && departInMin <= 5) {
            shouldNotify = true
          }
        } else {
          // Fallback: no ETA stored yet — fire when target is 25–35 min away
          if (minutesToTarget >= 25 && minutesToTarget <= 35) {
            shouldNotify = true
          }
        }

        if (!shouldNotify) continue

        await sendPush(profile.apns_token, {
          title: "Time to head out 🚗",
          body: `Leave now to make it to ${destName} on time`,
          event: "leave_now",
          meetupId: meetup.id,
        })
      }
    }

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-leave-now error:", err)
    return new Response("error", { status: 200 })
  }
})
