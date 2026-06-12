import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered by Postgres:
//   start_truth_or_dare(p_group_id != null) → push to every group
//   member except the starter.
// Payload: { sessionId: string, groupId: string, starterId: string }
serve(async (req) => {
  try {
    const { sessionId, groupId, starterId } = await req.json()
    if (!sessionId || !groupId || !starterId) {
      return new Response("ignored", { status: 200 })
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const [{ data: group }, { data: session }, { data: starter }, { data: members }] =
      await Promise.all([
        supabase.from("game_groups").select("name").eq("id", groupId).single(),
        supabase.from("game_sessions").select("invite_code").eq("id", sessionId).single(),
        supabase.from("profiles").select("display_name").eq("id", starterId).single(),
        supabase
          .from("game_group_members")
          .select("user_id, profiles!game_group_members_user_id_fkey(apns_token)")
          .eq("group_id", groupId)
          .neq("user_id", starterId),
      ])

    if (!group || !session?.invite_code || !members?.length) {
      return new Response("nothing to send", { status: 200 })
    }

    const starterName = starter?.display_name ?? "Someone"
    const tokens = members
      .map((m: { profiles: { apns_token: string | null } | null }) => m.profiles?.apns_token)
      .filter((t: string | null): t is string => !!t)

    await Promise.all(
      tokens.map((token: string) =>
        sendPush(token, {
          title: `🎮 ${group.name}`,
          body: `${starterName} started a game! Join with code ${session.invite_code}`,
          event: "game_group_start",
          senderId: starterId,
          sessionId,
        }),
      ),
    )

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-game-group-start error:", err)
    return new Response("error", { status: 200 })
  }
})
