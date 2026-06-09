import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered by Postgres:
//   AFTER INSERT ON friendships (status='pending') → push to recipient
//   AFTER UPDATE ON friendships (status='accepted') → push to requester
// Payload: { friendshipId: string, event: 'friend_request' | 'friend_accepted' }
serve(async (req) => {
  try {
    const { friendshipId, event } = await req.json()
    if (!["friend_request", "friend_accepted"].includes(event)) {
      return new Response("ignored", { status: 200 })
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    // friendships has a composite PK (user_a_id, user_b_id) plus an id and
    // initiated_by (the requester). The recipient is whichever side isn't the initiator.
    const { data: friendship, error: fErr } = await supabase
      .from("friendships")
      .select("user_a_id, user_b_id, initiated_by")
      .eq("id", friendshipId)
      .single()
    if (fErr || !friendship) return new Response("not found", { status: 200 })

    const requesterId = friendship.initiated_by
    const requesteeId =
      friendship.user_a_id === requesterId ? friendship.user_b_id : friendship.user_a_id

    const recipientId =
      event === "friend_request"
        ? requesteeId   // new request → notify the person being asked
        : requesterId   // accepted → notify the person who asked

    const actorId =
      event === "friend_request"
        ? requesterId
        : requesteeId

    const [{ data: recipient }, { data: actor }] = await Promise.all([
      supabase.from("profiles").select("apns_token").eq("id", recipientId).single(),
      supabase.from("profiles").select("display_name").eq("id", actorId).single(),
    ])

    if (!recipient?.apns_token) return new Response("no token", { status: 200 })

    const actorName = actor?.display_name ?? "Someone"

    if (event === "friend_request") {
      await sendPush(recipient.apns_token, {
        title: "New friend request",
        body: `${actorName} wants to be friends`,
        event: "friend_request",
        friendshipId,
      })
    } else {
      await sendPush(recipient.apns_token, {
        title: "Friend request accepted",
        body: `${actorName} accepted your friend request`,
        event: "friend_accepted",
        friendshipId,
      })
    }

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-friend-request error:", err)
    return new Response("error", { status: 200 })
  }
})
