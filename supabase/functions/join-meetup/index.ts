import { serve } from "https://deno.land/std@0.224.0/http/server.ts"

serve(async (req) => {
  const url = new URL(req.url)
  const parts = url.pathname.split("/")
  const token = parts[parts.length - 1]

  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Opening Squad Brunch...</title>
  <style>
    body { background: #0f0f1a; color: white; font-family: -apple-system, sans-serif;
           display: flex; flex-direction: column; align-items: center; justify-content: center;
           min-height: 100vh; margin: 0; text-align: center; padding: 24px; }
    h1 { font-size: 28px; font-weight: 800; margin-bottom: 8px; }
    p { color: rgba(255,255,255,0.6); font-size: 16px; }
    .badge { margin-top: 32px; opacity: 0; transition: opacity 0.5s; }
    .badge.show { opacity: 1; }
    .btn { display: inline-block; background: #6C57C5; color: white; padding: 14px 28px;
           border-radius: 14px; text-decoration: none; font-weight: 700; font-size: 16px; margin-top: 16px; }
  </style>
</head>
<body>
  <h1>Squad Brunch 🎯</h1>
  <p>Opening your invite...</p>
  <div class="badge" id="badge">
    <p>Don't have the app?</p>
    <a class="btn" href="https://apps.apple.com/app/squad-brunch/id000000000">Get Squad Brunch</a>
  </div>
  <script>
    window.location = 'squadbrunch://join/${token}';
    setTimeout(() => { document.getElementById('badge').classList.add('show'); }, 2000);
  </script>
</body>
</html>`

  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  })
})
