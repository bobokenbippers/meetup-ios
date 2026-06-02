import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const TEAM_ID = Deno.env.get("APPLE_TEAM_ID")!
const KEY_ID = Deno.env.get("APNS_KEY_ID")!
const BUNDLE_ID = "gautamlgtm.meetup-ios"
const USE_SANDBOX = Deno.env.get("APNS_USE_SANDBOX") === "true"
const APNS_HOST = USE_SANDBOX
  ? "api.sandbox.push.apple.com"
  : "api.push.apple.com"

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s/g, "")
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

let _cachedJwt: string | null = null
let _cachedJwtAt = 0

async function apnsJwt(): Promise<string> {
  const now = Date.now() / 1000
  // APNs tokens expire after 60 min; regenerate after 55
  if (_cachedJwt && now - _cachedJwtAt < 55 * 60) return _cachedJwt

  const keyPem = Deno.env.get("APNS_AUTH_KEY")!
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(keyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  )
  _cachedJwt = await create(
    { alg: "ES256", kid: KEY_ID, typ: "JWT" },
    { iss: TEAM_ID, iat: getNumericDate(0) },
    key,
  )
  _cachedJwtAt = now
  return _cachedJwt
}

export interface PushPayload {
  title: string
  body: string
  event: string
  meetupId?: string
  friendshipId?: string
  badge?: number
}

export async function sendPush(token: string, payload: PushPayload): Promise<void> {
  const jwt = await apnsJwt()
  const apnsPayload = {
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
      badge: payload.badge,
    },
    event: payload.event,
    ...(payload.meetupId ? { meetupId: payload.meetupId } : {}),
    ...(payload.friendshipId ? { friendshipId: payload.friendshipId } : {}),
  }

  const url = `https://${APNS_HOST}/3/device/${token}`
  let res = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": BUNDLE_ID,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(apnsPayload),
  })

  // Retry once on transient 5xx
  if (res.status >= 500) {
    res = await fetch(url, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": BUNDLE_ID,
        "apns-push-type": "alert",
        "content-type": "application/json",
      },
      body: JSON.stringify(apnsPayload),
    })
  }

  if (res.status === 410) {
    // Token stale — clear it so we don't keep retrying
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )
    await supabase
      .from("profiles")
      .update({ apns_token: null })
      .eq("apns_token", token)
    return
  }

  if (res.status >= 400) {
    const body = await res.text()
    console.error(`APNs error ${res.status} for token ${token.slice(0, 8)}…: ${body}`)
  }
}
