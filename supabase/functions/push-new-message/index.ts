import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendPush } from "../_shared/apns.ts"

// Triggered by Postgres:
//   AFTER INSERT ON messages → push to the other participant.
// Payload: { messageId: string }
serve(async (req) => {
  try {
    const { messageId } = await req.json()
    if (!messageId) return new Response("ignored", { status: 200 })

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const { data: message, error: mErr } = await supabase
      .from("messages")
      .select("id, conversation_id, sender_id, body, image_path")
      .eq("id", messageId)
      .single()
    if (mErr || !message) return new Response("not found", { status: 200 })

    const { data: conversation, error: cErr } = await supabase
      .from("conversations")
      .select("user_a_id, user_b_id")
      .eq("id", message.conversation_id)
      .single()
    if (cErr || !conversation) return new Response("no conversation", { status: 200 })

    const recipientId =
      conversation.user_a_id === message.sender_id
        ? conversation.user_b_id
        : conversation.user_a_id

    const [{ data: recipient }, { data: sender }] = await Promise.all([
      supabase.from("profiles").select("apns_token").eq("id", recipientId).single(),
      supabase.from("profiles").select("display_name").eq("id", message.sender_id).single(),
    ])

    if (!recipient?.apns_token) return new Response("no token", { status: 200 })

    const senderName = sender?.display_name ?? "Someone"
    const preview = message.body && message.body.length > 0
      ? message.body
      : (message.image_path ? "📷 Photo" : "New message")

    await sendPush(recipient.apns_token, {
      title: senderName,
      body: preview,
      event: "new_message",
      conversationId: message.conversation_id,
      senderId: message.sender_id,
    })

    return new Response("ok", { status: 200 })
  } catch (err) {
    console.error("push-new-message error:", err)
    return new Response("error", { status: 200 })
  }
})
