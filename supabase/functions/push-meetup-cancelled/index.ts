import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered by Postgres: AFTER UPDATE ON meetups when status flips to 'cancelled'.
// Notifies every participant who hadn't bailed (invited / accepted / arrived),
// excluding the host who performed the cancellation.
// Payload: { meetupId: string }
serve(async (req) => {
  try {
    const { meetupId } = await req.json()
    if (!meetupId) return new Response("missing fields", { status: 200 })

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const { data: meetup } = await supabase
      .from("meetups")
      .select("host_id, destination_name")
      .eq("id", meetupId)
      .single()

    const meetupName = meetup?.destination_name ?? "your meetup"

    const { data: recipients } = await supabase
      .from("meetup_participants")
      .select("user_id, profiles(apns_token)")
      .eq("meetup_id", meetupId)
      .in("status", ["invited", "accepted", "arrived"])
      .neq("user_id", meetup?.host_id ?? "")

    const tokens = (recipients ?? [])
      .map((r: any) => r.profiles?.apns_token)
      .filter(Boolean)

    if (tokens.length === 0) return new Response("no recipients", { status: 200 })

    await Promise.all(
      tokens.map((token: string) =>
        sendPush(token, {
          title: "Meetup cancelled",
          body: `${meetupName} has been cancelled`,
          event: "meetup_cancelled",
          meetupId: meetupId,
        }),
      ),
    )

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-meetup-cancelled error:", err)
    return new Response("error", { status: 200 }) // always 200 so pg_net doesn't retry forever
  }
})
