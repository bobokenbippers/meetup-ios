import { serve } from "https://deno.land/std@0.224.0/http/server.ts"

// parse-receipt
// ----------------------------------------------------------------------------
// Vision-LLM receipt parsing. Accepts a base64-encoded receipt image, sends it
// to OpenAI (vision) with a strict JSON schema, and returns clean structured
// line items plus printed subtotal/tax/total.
//
// The iOS client keeps the local Apple Vision + regex parser as a graceful
// fallback, so this function only needs to succeed on the happy path — when it
// errors, the client silently falls back.
//
// Secret: OPENAI_API_KEY must be set as a Supabase secret. NEVER hardcode it.
//   supabase secrets set OPENAI_API_KEY=sk-...
//
// Model: gpt-4o-mini — strong vision quality at very low cost. Receipts are
// small images and the output is a short JSON object, so a single call is
// fractions of a cent (~$0.0007) and typically returns in 2-6s.
// ----------------------------------------------------------------------------

const OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"
const MODEL = "gpt-4o-mini"

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  })
}

// Strict schema for the structured response. The model is constrained to emit
// exactly this shape via response_format json_schema (strict mode). OpenAI
// strict mode requires every property listed in `required` and
// additionalProperties:false on every object — both hold here.
const RECEIPT_SCHEMA = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string", description: "Line-item name as printed" },
          qty: {
            type: "integer",
            description: "Quantity ordered. 1 if not specified.",
          },
          unitPrice: {
            type: "number",
            description: "Price for a single unit",
          },
          lineTotal: {
            type: "number",
            description: "qty * unitPrice as printed on the receipt",
          },
          isModifier: {
            type: "boolean",
            description:
              "True for no-price modifier/option lines that belong to the item above (e.g. '(2) Woodford RX'), false for real billable items.",
          },
        },
        required: ["name", "qty", "unitPrice", "lineTotal", "isModifier"],
        additionalProperties: false,
      },
    },
    subtotal: { type: "number" },
    tax: { type: "number" },
    tip: { type: "number" },
    total: { type: "number" },
  },
  required: ["items", "subtotal", "tax", "tip", "total"],
  additionalProperties: false,
}

const SYSTEM_PROMPT = [
  "You are a precise receipt-parsing engine for a bill-splitting app.",
  "You are given a photo of a restaurant or bar receipt. Extract every billable line item plus the printed totals.",
  "",
  "Rules:",
  "- Return ONE entry per printed line item. Do NOT pre-expand quantities — set qty to the printed quantity and the app will expand it.",
  "- unitPrice is the per-unit price; lineTotal is what is actually charged for that line (qty * unitPrice).",
  "- For lines like '2 @ $16.00 = $32.00', qty=2, unitPrice=16.00, lineTotal=32.00.",
  "- A modifier/option line that has NO price of its own (e.g. '(2) Woodford RX' under an Old Fashioned) is part of the item above it. Mark it isModifier=true with unitPrice 0 and lineTotal 0. Do NOT invent a price for it.",
  "- Do NOT include subtotal, tax, tip, gratuity, service charge, surcharge, or total as items. Report those in their dedicated fields.",
  "- If tip/gratuity is not printed, set tip to 0.",
  "- Use the printed subtotal, tax, and total verbatim. Do not recompute or 'correct' them.",
  "- Prices are numbers without a currency symbol.",
].join("\n")

interface UpstreamError {
  status: number
  message: string
}

async function callOpenAI(
  apiKey: string,
  base64Image: string,
  mediaType: string,
): Promise<unknown> {
  const res = await fetch(OPENAI_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 4096,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "receipt",
          strict: true,
          schema: RECEIPT_SCHEMA,
        },
      },
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Parse this receipt and return the structured JSON.",
            },
            {
              type: "image_url",
              image_url: {
                url: `data:${mediaType};base64,${base64Image}`,
              },
            },
          ],
        },
      ],
    }),
  })

  if (!res.ok) {
    const text = await res.text()
    const err: UpstreamError = { status: res.status, message: text }
    throw err
  }

  const payload = await res.json()

  const choice = (payload.choices ?? [])[0]
  if (!choice) {
    throw { status: 502, message: "Empty response from model." } as UpstreamError
  }
  // Structured-output refusal surfaces as message.refusal.
  if (choice.message?.refusal) {
    throw {
      status: 422,
      message: `Model refused: ${choice.message.refusal}`,
    } as UpstreamError
  }
  if (choice.finish_reason === "content_filter") {
    throw { status: 422, message: "Model refused to parse the image." } as UpstreamError
  }

  // response_format json_schema guarantees message.content is valid JSON
  // matching the schema.
  const content = choice.message?.content
  if (typeof content !== "string" || !content) {
    throw { status: 502, message: "Empty response from model." } as UpstreamError
  }

  return JSON.parse(content)
}

// Validate and normalize the parsed structure into the exact shape the client
// expects. Throws on anything malformed so the client can fall back.
function validate(parsed: unknown) {
  if (typeof parsed !== "object" || parsed === null) {
    throw { status: 502, message: "Parsed result is not an object." } as UpstreamError
  }
  const p = parsed as Record<string, unknown>
  if (!Array.isArray(p.items)) {
    throw { status: 502, message: "Parsed result missing items array." } as UpstreamError
  }

  const num = (v: unknown): number =>
    typeof v === "number" && isFinite(v) ? v : 0

  const items = p.items.map((raw) => {
    const it = (raw ?? {}) as Record<string, unknown>
    const qtyRaw = num(it.qty)
    const qty = qtyRaw >= 1 ? Math.round(qtyRaw) : 1
    return {
      name: typeof it.name === "string" ? it.name.trim() : "",
      qty,
      unitPrice: num(it.unitPrice),
      lineTotal: num(it.lineTotal),
      isModifier: it.isModifier === true,
    }
  })

  return {
    items,
    subtotal: num(p.subtotal),
    tax: num(p.tax),
    tip: num(p.tip),
    total: num(p.total),
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS })
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405)
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY")
  if (!apiKey) {
    return json({ error: "OPENAI_API_KEY is not configured." }, 500)
  }

  let body: { image?: string; mediaType?: string }
  try {
    body = await req.json()
  } catch {
    return json({ error: "Invalid JSON body." }, 400)
  }

  const base64Image = (body.image ?? "").trim()
  if (!base64Image) {
    return json({ error: "Missing 'image' (base64) in request body." }, 400)
  }
  // Accept JPEG/PNG/WebP/GIF; default to JPEG since the client encodes JPEG.
  const allowed = ["image/jpeg", "image/png", "image/webp", "image/gif"]
  const mediaType =
    body.mediaType && allowed.includes(body.mediaType)
      ? body.mediaType
      : "image/jpeg"

  try {
    const parsed = await callOpenAI(apiKey, base64Image, mediaType)
    const result = validate(parsed)
    return json(result, 200)
  } catch (e) {
    const err = e as UpstreamError
    const status = typeof err.status === "number" ? err.status : 500
    console.error("parse-receipt failed:", status, err.message)
    // Surface a clean error; the client falls back to its local parser.
    return json({ error: "Receipt parsing failed.", detail: err.message }, status)
  }
})
