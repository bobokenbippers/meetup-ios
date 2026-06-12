import { serve } from "https://deno.land/std@0.224.0/http/server.ts"

serve(async (req) => {
  const url = new URL(req.url)
  const parts = url.pathname.split("/")
  const token = parts[parts.length - 1]?.trim()

  if (!token) {
    return new Response("Invite link is missing a token.", {
      status: 400,
      headers: { "content-type": "text/plain; charset=utf-8" },
    })
  }

  const appURL = `squadbrunch://join/${encodeURIComponent(token)}`
  const userAgent = req.headers.get("user-agent") ?? ""
  const isAppleMobile = /iPhone|iPad|iPod/i.test(userAgent)

  if (isAppleMobile) {
    return new Response(null, {
      status: 302,
      headers: {
        location: appURL,
        "cache-control": "no-store",
      },
    })
  }

  return new Response(
    [
      "Squad Brunch invite",
      "",
      "Open this link on your iPhone with the Squad Brunch TestFlight build installed.",
      "",
      `Direct app link: ${appURL}`,
    ].join("\n"),
    {
      headers: {
        "content-type": "text/plain; charset=utf-8",
        "cache-control": "no-store",
      },
    },
  )
})
