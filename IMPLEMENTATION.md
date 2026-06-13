# Meetup Tracker — Implementation Plan

This document is the precise, exhaustive build plan. It assumes the reader is the builder (or an AI coding assistant) and gives concrete commands, schemas, code snippets, and acceptance criteria for each milestone.

For the conceptual overview, read `GUIDE.md` first.

> **Migration history:** `supabase/migrations/` contains the canonical SQL migration files for this project. Apply them in filename order against your Supabase project using the SQL editor or the Supabase CLI (`supabase db push`). Do not apply schema changes outside of this directory.

## Current Schema Notes

- `meetup_late_punishment_votes` stores one punishment vote per meetup participant. Votes are keyed by `(meetup_id, voter_id)` and use fixed `option_key` values: `appetizer`, `dare`, `group_photo`, `next_spot`, `best_excuse`.
- `meetup_late_punishment_proofs` stores proof photos for completed late punishments. Proof images are stored in the existing `meetup-photos` bucket and referenced by storage path.
- `vote_late_punishment(p_meetup_id, p_option_key)` is the write path for late-punishment votes. It requires the caller to be in the meetup and rejects callers who are currently late for that meetup, so late participants cannot vote on their own punishment.

---

## 0. Pre-Build Setup

Complete this before M1. None of this is coding; it's accounts and tooling.

### 0.1 Accounts to Create

| Account | URL | Purpose | Time |
|---|---|---|---|
| Apple Developer Program | developer.apple.com/programs | Sign in with Apple, APNs, TestFlight | $99/yr; **24–48 hr approval** — start first |
| Supabase | supabase.com | Database, auth, realtime | Free; instant |
| Mapbox | mapbox.com | Routing API for ETA computation | Free; instant |
| GitHub | github.com | Source control | Free; instant |

### 0.2 Apple Developer Setup

In **developer.apple.com → Certificates, Identifiers & Profiles**:

1. **Identifiers → App IDs → Create**
   - Description: "Meetup Tracker"
   - Bundle ID: `com.{yourname}.meetup` (use your real name; this must be globally unique)
   - Capabilities: enable **Sign in with Apple**, **Push Notifications**, **Background Modes**

2. **Identifiers → Services IDs → Create** (this is what Supabase will use)
   - Description: "Meetup Tracker Auth Service"
   - Identifier: `com.{yourname}.meetup.service`
   - Enable **Sign in with Apple**
   - Configure: Primary App ID = your App ID from step 1
   - Domains: leave blank for now (Supabase will tell you what to put here in step 0.3)
   - Return URLs: leave blank for now

3. **Keys → Create**
   - Name: "Sign in with Apple Key"
   - Enable **Sign in with Apple**
   - Configure: Primary App ID = your App ID
   - Download the `.p8` file (you can only download it once — save it in your password manager)
   - Note the Key ID (10 chars)

4. **Keys → Create** (a second key for APNs)
   - Name: "APNs Key"
   - Enable **Apple Push Notifications service (APNs)**
   - Download the `.p8` file
   - Note the Key ID

5. **Note your Team ID** — top right of the developer portal under your name (10 chars)

Save these in your password manager:
- Team ID
- App Bundle ID
- Service ID
- Sign-in-with-Apple Key ID + `.p8` contents
- APNs Key ID + `.p8` contents

### 0.3 Supabase Project Setup

In **supabase.com**:

1. **New Project** → name it `meetup-tracker`, pick region nearest to you, generate a strong DB password (save in password manager)
2. Wait for provisioning (~2 min)
3. **Authentication → Providers → Apple** → toggle on
   - Service ID: from 0.2 step 2
   - Team ID: from 0.2 step 5
   - Key ID: from 0.2 step 3
   - Secret Key: paste the `.p8` file contents
   - Copy the "Callback URL" Supabase displays
4. Go back to Apple Developer → your Service ID → configure:
   - Domains: the Supabase callback URL's domain (e.g. `xxxxxxx.supabase.co`)
   - Return URLs: paste the full Supabase callback URL
   - Save

5. In Supabase: **Project Settings → API**
   - Copy `Project URL` → save as `SUPABASE_URL`
   - Copy `anon public` key → save as `SUPABASE_ANON_KEY`
   - Copy `service_role secret` key → save as `SUPABASE_SERVICE_KEY` (backend only — never ship this in the iOS app)

6. **Database → Extensions** → enable `postgis`

### 0.4 Mapbox Setup

1. Sign up at mapbox.com
2. Account → Tokens → create a new token with these scopes:
   - `directions:read`
   - `geocoding:read`
3. Save token as `MAPBOX_ACCESS_TOKEN`

### 0.5 Local Tooling

```bash
# macOS
brew install python@3.11
brew install --cask xcode  # if not already installed
brew install postgresql@16  # for local dev/testing only

# Open Xcode once to accept license, install components

# Python tooling
pip3 install --user uv  # fast Python package manager

# Verify versions
python3 --version  # should be 3.11+
xcodebuild -version  # should be Xcode 15+
```

### 0.6 Repository Structure

Create one monorepo with two top-level directories:

```bash
mkdir meetup-tracker && cd meetup-tracker
git init
mkdir ios backend
echo "node_modules/\n.DS_Store\n*.xcuserdata\n.env\n*.p8\nvenv/\n__pycache__/\n*.pyc\n.pytest_cache/" > .gitignore
git add . && git commit -m "initial structure"
```

### 0.7 Secrets File (backend, never commit)

```bash
cd backend
cat > .env <<EOF
SUPABASE_URL=
SUPABASE_SERVICE_KEY=
MAPBOX_ACCESS_TOKEN=
APPLE_TEAM_ID=
APPLE_BUNDLE_ID=com.yourname.meetup
APNS_KEY_ID=
APNS_KEY_PATH=./secrets/apns_key.p8
EOF
mkdir secrets
# Move your APNs .p8 file into ./secrets/apns_key.p8
```

Add `.env` and `secrets/` to `.gitignore` (already done above).

### 0.8 Acceptance Criteria for Pre-Build

- [ ] Apple Developer account approved
- [ ] App ID and Service ID created with correct capabilities
- [ ] Both `.p8` keys downloaded and saved in password manager
- [ ] Supabase project provisioned, Apple provider configured, callback URL pasted into Apple Service ID
- [ ] PostGIS extension enabled in Supabase
- [ ] Mapbox token saved
- [ ] Local Python and Xcode installed
- [ ] Monorepo with `ios/` and `backend/` directories committed to git

---

## M1 — Auth Working End-to-End

**Goal:** User taps "Sign in with Apple" in the iOS app, completes Face ID, sees a "Hello, {name}" screen. A `users` row exists in Supabase. JWT issued by Supabase is stored on device.

**Estimated time:** 1 weekend.

### M1.1 Database Schema

In Supabase SQL editor, run:

```sql
-- Profile data linked to Supabase's built-in auth.users table.
-- Supabase handles the auth.users row; we add app-specific profile data.
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  display_name    text,
  phone_e164      text unique,
  apns_token      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index profiles_phone_idx on public.profiles(phone_e164);

-- Row-Level Security
alter table public.profiles enable row level security;

create policy "users can read their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

create policy "users can insert their own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Auto-create profile row when a new auth.users row is created.
-- Captures display_name and phone from the metadata Apple sends on first login.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      'New User'
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

**Why this works:** Supabase's `auth.users` table stores the Apple `sub` and the metadata Apple sends on first login. Our `profiles` table holds app-specific fields. The trigger captures the display name on first login automatically — solving the "Apple only sends name once" bug.

### M1.2 iOS Project Creation

1. Open Xcode → **File → New → Project → iOS App**
2. Settings:
   - Product Name: `MeetupTracker`
   - Team: your Apple Developer team
   - Organization Identifier: `com.{yourname}` (so Bundle ID matches your App ID)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None** (we'll use Supabase)
3. Save it inside the `ios/` directory of your repo

### M1.3 iOS Capabilities

Project → target → **Signing & Capabilities**:

1. Verify Team and Bundle ID match Apple Developer setup
2. **+ Capability → Sign in with Apple**
3. **+ Capability → Push Notifications**
4. **+ Capability → Background Modes** → check:
   - Location updates
   - Audio, AirPlay, and Picture in Picture
   - Remote notifications
   - Background fetch

### M1.4 Info.plist Keys

Add these keys to Info.plist (right-click → Open As → Source Code, or use the Info tab):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Meetup Tracker uses your location to show your route to the meetup destination and your ETA to friends in the meetup.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>To keep your friends updated on your ETA even when the app is in your pocket, Meetup Tracker needs background location access during active meetups. Sharing only happens during meetups you've explicitly joined.</string>

<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>remote-notification</string>
  <string>fetch</string>
  <string>audio</string>
</array>
```

The wording matters — Apple reviews these strings. Be specific about *why* you need the permission and *when* it's used.

### M1.5 Supabase Swift SDK

In Xcode: **File → Add Package Dependencies**:

```
https://github.com/supabase/supabase-swift
```

Add `Supabase` to your target.

### M1.6 Supabase Client

Create `MeetupTracker/Services/SupabaseManager.swift`:

```swift
import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        // TODO: Move these to a config file checked into git
        // (anon key is safe to ship in the iOS app — RLS protects data)
        let url = URL(string: "PASTE_SUPABASE_URL_HERE")!
        let anonKey = "PASTE_SUPABASE_ANON_KEY_HERE"
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }
}
```

### M1.7 Auth Models

Create `MeetupTracker/Models/Profile.swift`:

```swift
import Foundation

struct Profile: Codable, Identifiable {
    let id: UUID
    var displayName: String?
    var phoneE164: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case phoneE164 = "phone_e164"
    }
}
```

### M1.8 Auth ViewModel

Create `MeetupTracker/ViewModels/AuthViewModel.swift`:

```swift
import Foundation
import AuthenticationServices
import Supabase
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var session: Session?
    @Published var profile: Profile?
    @Published var error: String?
    @Published var isLoading = false

    private let supabase = SupabaseManager.shared.client
    private var authTask: Task<Void, Never>?

    init() {
        authTask = Task {
            for await (event, session) in await supabase.auth.authStateChanges {
                self.session = session
                if event == .signedIn, let session = session {
                    await loadProfile(userId: session.user.id)
                }
                if event == .signedOut {
                    self.profile = nil
                }
            }
        }
    }

    func signInWithApple(authorization: ASAuthorization) async {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            error = "Invalid Apple credential"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: identityToken)
            )

            // Capture the name on first login. Apple only sends it once.
            if let fullName = credential.fullName {
                let displayName = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !displayName.isEmpty, let userId = session?.user.id {
                    try? await supabase
                        .from("profiles")
                        .update(["display_name": displayName])
                        .eq("id", value: userId)
                        .execute()
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadProfile(userId: UUID) async {
        do {
            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            self.profile = profile
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }
}
```

### M1.9 Sign-In View

Create `MeetupTracker/Views/SignInView.swift`:

```swift
import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)
                Text("Meetup Tracker")
                    .font(.largeTitle.bold())
                Text("Know who's on their way.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task {
                    switch result {
                    case .success(let auth):
                        await self.auth.signInWithApple(authorization: auth)
                    case .failure(let error):
                        self.auth.error = error.localizedDescription
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 40)

            if let error = auth.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Spacer().frame(height: 40)
        }
    }
}
```

### M1.10 Home View (placeholder)

Create `MeetupTracker/Views/HomeView.swift`:

```swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Hello, \(auth.profile?.displayName ?? "there")!")
                    .font(.largeTitle.bold())
                Text("Auth is working.")
                    .foregroundStyle(.secondary)

                Button("Sign Out") {
                    Task { await auth.signOut() }
                }
                .padding(.top, 32)
            }
            .navigationTitle("Meetup Tracker")
        }
    }
}
```

### M1.11 Root App

Replace `MeetupTrackerApp.swift`:

```swift
import SwiftUI

@main
struct MeetupTrackerApp: App {
    @StateObject private var auth = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.session == nil {
                    SignInView()
                } else {
                    HomeView()
                }
            }
            .environmentObject(auth)
        }
    }
}
```

### M1.12 Acceptance Criteria for M1

- [ ] App launches on simulator/device, shows Sign In screen
- [ ] Tapping "Sign in with Apple" presents Apple's native sheet
- [ ] After auth, app shows "Hello, {your name}!"
- [ ] In Supabase dashboard, `auth.users` shows a row with provider=apple
- [ ] In Supabase dashboard, `public.profiles` shows a row with `display_name` populated
- [ ] App relaunch keeps you signed in (session persists)
- [ ] Sign Out button returns you to Sign In screen
- [ ] Code committed to git on a `m1-auth` branch

### M1.13 M1 Watch-Outs

- The display name capture *only works on the first login per Apple ID*. To re-test, go to **Settings → your name → Sign-In & Security → Apps Using Apple ID → Meetup Tracker → Stop Using Apple ID**, then re-auth.
- If the Apple sign-in sheet doesn't appear or errors immediately, check that Bundle ID in Xcode matches App ID in Apple Developer Portal exactly.
- If Supabase rejects the token, double-check the Service ID configuration in Apple Developer (callback URL must be exact).

---

## M2 — Friends

**Goal:** Two test accounts can find each other by phone number, send a friend request, accept it, and both see each other in their friends list. Push notification fires on incoming request.

**Estimated time:** 1 weekend.

### M2.1 Schema Additions

In Supabase SQL editor:

```sql
-- Friendships use a "smaller user UUID first" canonicalization to avoid
-- duplicate rows for (a,b) and (b,a).
create table public.friendships (
  id              uuid primary key default gen_random_uuid(),
  user_a_id       uuid not null references public.profiles(id) on delete cascade,
  user_b_id       uuid not null references public.profiles(id) on delete cascade,
  status          text not null check (status in ('pending', 'accepted', 'blocked')),
  initiated_by    uuid not null references public.profiles(id) on delete cascade,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint user_a_lt_user_b check (user_a_id < user_b_id),
  unique (user_a_id, user_b_id)
);

create index friendships_user_a_idx on public.friendships(user_a_id);
create index friendships_user_b_idx on public.friendships(user_b_id);

alter table public.friendships enable row level security;

create policy "users see friendships they're part of"
  on public.friendships for select
  using (auth.uid() = user_a_id or auth.uid() = user_b_id);

create policy "users can create friend requests they initiate"
  on public.friendships for insert
  with check (auth.uid() = initiated_by
              and (auth.uid() = user_a_id or auth.uid() = user_b_id));

create policy "users can update friendships they're part of"
  on public.friendships for update
  using (auth.uid() = user_a_id or auth.uid() = user_b_id);

-- Required for decline (delete pending row) and removeFriend
create policy "users can delete friendships they're part of"
  on public.friendships for delete
  using (auth.uid() = user_a_id or auth.uid() = user_b_id);

-- NOTE: The initiated_by column tracks direction. user_a_id < user_b_id is enforced
-- by the check constraint. iOS always sets initiated_by = auth.uid() and orders
-- user_a_id/user_b_id by UUID string comparison (min < max).
-- Incoming requests: status='pending' AND initiated_by != auth.uid()
-- Outgoing pending: status='pending' AND initiated_by = auth.uid()
-- Accepted friends: status='accepted'

-- Helper: search profiles by phone (only returns the matched profile, no listing)
create or replace function public.find_user_by_phone(search_phone text)
returns table (id uuid, display_name text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.display_name
  from public.profiles p
  where p.phone_e164 = search_phone
  limit 1;
$$;
```

### M2.4 Friendship Gate on Meetup Invites (June 2026)

Meetup invitations are gated behind an **accepted** friendship. A host can only insert a
`meetup_participants` row for themselves or for a user who is an accepted friend, in either
canonical friendship direction. Pending/declined friendships do **not** unlock invites.
Existing participant rows are untouched — the gate applies to new INSERTs only.

```sql
-- Helper: is p_user_id an accepted friend of p_host_id (either direction)?
create or replace function public.is_accepted_friend(p_host_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and (
        (f.user_a_id = p_host_id and f.user_b_id = p_user_id)
        or (f.user_a_id = p_user_id and f.user_b_id = p_host_id)
      )
  );
$$;

-- Replaces the old "host can add anyone" INSERT policy.
drop policy if exists participants_insert on public.meetup_participants;

create policy participants_insert
  on public.meetup_participants for insert
  with check (
    is_meetup_host(meetup_id)
    and (
      user_id = auth.uid()                          -- host inserting their own row
      or public.is_accepted_friend(auth.uid(), user_id)  -- host inviting an accepted friend
    )
  );
```

`is_meetup_host(p_meetup_id)` is the existing `SECURITY DEFINER` helper
(`select exists (select 1 from meetups where id = p_meetup_id and host_id = auth.uid())`).

iOS surfaces only accepted friends in the invite picker; phone-search / contact selection of a
non-friend shows **"Send friend request"** (or **"Request pending"** / **"Accept request"**)
instead of **Add**, via `MeetupService.friendshipStatus(with:)`.

> **Insert ordering (required by this gate):** `MeetupService.createMeetup` must insert
> the host's own `meetup_participants` row in its **own** statement and then insert each
> invitee **individually** — never host + invitees in one atomic `insert([...])`. Because
> `participants_insert` is evaluated per row, a single non-accepted-friend invitee in a
> batch rolls back the entire insert (host row + every other invite), orphaning the meetup
> with zero participants so it surfaces for no one — neither the host nor the invitees.
> Per-row inserts isolate a gate rejection to just that invitee. (Fixed in
> `fix/invites-not-surfacing`.)

### M2.2 Profile Phone Number Setup

Add a "complete your profile" flow that runs after first sign-in if `phone_e164` is null. Create `MeetupTracker/Views/ProfileSetupView.swift`:

```swift
import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var phone: String = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("One more thing")
                .font(.largeTitle.bold())
            Text("Add your phone number so friends can find you.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("+1 555 555 5555", text: $phone)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.phonePad)
                .padding(.horizontal)

            Button("Save") {
                Task { await save() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || normalizedPhone == nil)

            if let error = error {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
        .padding()
    }

    private var normalizedPhone: String? {
        // Very simple E.164 normalization. Production: use libphonenumber.
        let stripped = phone.filter { $0.isNumber || $0 == "+" }
        guard stripped.hasPrefix("+"), stripped.count >= 10 else { return nil }
        return stripped
    }

    private func save() async {
        guard let phone = normalizedPhone, let userId = auth.session?.user.id else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await SupabaseManager.shared.client
                .from("profiles")
                .update(["phone_e164": phone])
                .eq("id", value: userId)
                .execute()
            await auth.loadProfile(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

Update `MeetupTrackerApp.swift` routing:

```swift
Group {
    if auth.session == nil {
        SignInView()
    } else if auth.profile?.phoneE164 == nil {
        ProfileSetupView()
    } else {
        HomeView()
    }
}
```

### M2.3 Friends Service

Create `MeetupTracker/Services/FriendsService.swift`:

```swift
import Foundation
import Supabase

struct Friend: Codable, Identifiable {
    let id: UUID
    let displayName: String?
    let status: String  // 'pending' | 'accepted'
    let initiatedByMe: Bool
}

final class FriendsService {
    static let shared = FriendsService()
    private let supabase = SupabaseManager.shared.client

    func findByPhone(_ phone: String) async throws -> (id: UUID, name: String)? {
        let result: [SearchResult] = try await supabase
            .rpc("find_user_by_phone", params: ["search_phone": phone])
            .execute()
            .value
        return result.first.map { ($0.id, $0.displayName ?? "Unknown") }
    }

    func sendRequest(toUserId: UUID) async throws {
        guard let myId = supabase.auth.currentUser?.id else { return }
        let (a, b) = myId.uuidString < toUserId.uuidString ? (myId, toUserId) : (toUserId, myId)
        try await supabase.from("friendships").insert([
            "user_a_id": a.uuidString,
            "user_b_id": b.uuidString,
            "status": "pending",
            "initiated_by": myId.uuidString,
        ]).execute()
    }

    func accept(friendshipId: UUID) async throws {
        try await supabase
            .from("friendships")
            .update(["status": "accepted"])
            .eq("id", value: friendshipId)
            .execute()
    }

    func listFriends() async throws -> [Friend] {
        // Query both directions, normalize to "the other user"
        // Implementation: server-side view or two-query stitching
        // For brevity, see full code in repo
        return []
    }

    private struct SearchResult: Codable {
        let id: UUID
        let displayName: String?
        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }
}
```

### M2.4 Friends UI

Create `FriendsListView.swift`, `AddFriendView.swift`, `IncomingRequestsView.swift`. Wire them into a tab bar in `HomeView`:

```swift
TabView {
    MeetupsListView()
        .tabItem { Label("Meetups", systemImage: "person.2.circle") }
    FriendsListView()
        .tabItem { Label("Friends", systemImage: "person.crop.circle") }
    SettingsView()
        .tabItem { Label("Settings", systemImage: "gear") }
}
```

(For the full UI implementation, generate it idiomatically using SwiftUI standard patterns: `List` with sections, `Button("Add Friend")` toolbar button presenting a sheet, real-time updates via Supabase subscriptions. The data layer is the constrained part; the UI is taste.)

### M2.5 Push Notifications — Backend Setup

Create `backend/` Python project:

```bash
cd backend
uv venv
source .venv/bin/activate
uv pip install fastapi uvicorn httpx pyjwt[crypto] python-dotenv supabase apns2
```

Create `backend/main.py`:

```python
import os
import asyncio
from fastapi import FastAPI, Request, HTTPException
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

app = FastAPI()
supabase: Client = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_SERVICE_KEY"],
)

@app.get("/health")
def health():
    return {"ok": True}

# Supabase webhook for friendship inserts → triggers push to recipient
@app.post("/webhooks/friendship-inserted")
async def friendship_inserted(request: Request):
    payload = await request.json()
    record = payload.get("record", {})
    if record.get("status") != "pending":
        return {"ok": True}

    initiator_id = record["initiated_by"]
    recipient_id = (
        record["user_a_id"] if record["user_b_id"] == initiator_id
        else record["user_b_id"]
    )

    # Look up recipient APNs token
    profile = supabase.table("profiles").select("apns_token, display_name").eq("id", recipient_id).single().execute()
    apns_token = profile.data.get("apns_token")
    if not apns_token:
        return {"ok": True}

    initiator = supabase.table("profiles").select("display_name").eq("id", initiator_id).single().execute()
    initiator_name = initiator.data.get("display_name", "Someone")

    await send_apns_push(
        token=apns_token,
        title="New friend request",
        body=f"{initiator_name} wants to be friends.",
        data={"type": "friend_request", "from_id": initiator_id},
    )
    return {"ok": True}


async def send_apns_push(token: str, title: str, body: str, data: dict):
    # apns2 sync client wrapped in to_thread for async use
    from apns2.client import APNsClient
    from apns2.payload import Payload
    from apns2.credentials import TokenCredentials

    creds = TokenCredentials(
        auth_key_path=os.environ["APNS_KEY_PATH"],
        auth_key_id=os.environ["APNS_KEY_ID"],
        team_id=os.environ["APPLE_TEAM_ID"],
    )
    client = APNsClient(credentials=creds, use_sandbox=True)  # sandbox for dev
    payload = Payload(alert={"title": title, "body": body}, sound="default", custom=data)
    await asyncio.to_thread(
        client.send_notification, token, payload, os.environ["APPLE_BUNDLE_ID"]
    )
```

Run:
```bash
uvicorn main:app --reload --port 8000
```

### M2.6 Wire Up Webhook in Supabase

In Supabase: **Database → Webhooks → Create Webhook**:
- Name: `friendship-inserted`
- Table: `public.friendships`
- Events: Insert
- HTTP method: POST
- URL: your backend URL (use ngrok during dev: `ngrok http 8000`, paste the https URL)

### M2.7 iOS Push Notification Registration

In `MeetupTrackerApp.swift`, add an `AppDelegate`:

```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
            try? await SupabaseManager.shared.client
                .from("profiles")
                .update(["apns_token": token])
                .eq("id", value: userId)
                .execute()
        }
    }
}

@main
struct MeetupTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // ... rest unchanged
}
```

### M2.8 Acceptance Criteria for M2

- [ ] User completes phone number setup after first sign-in
- [ ] User can search for another user by phone, send a friend request
- [ ] Recipient receives push notification: "{Name} wants to be friends"
- [ ] Recipient sees the pending request in their UI, can accept
- [ ] After acceptance, both users see each other in their friends list
- [ ] APNs token is saved to `profiles.apns_token` on launch
- [ ] Code committed on `m2-friends` branch

### M2.9 M2 Watch-Outs

- APNs sandbox vs production: use `use_sandbox=True` for development builds, `False` for TestFlight/production
- ngrok URLs change every time you restart it — re-update the Supabase webhook URL
- Push permission prompt only shows once. To re-test: delete app, reinstall

---

## M3 — Meetups + Dashboard (Static)

**Goal:** User creates a meetup with destination + target time + invitees. Invitees receive push, can accept/decline. Dashboard shows participant tiles colored by acceptance status. No live location yet.

**Estimated time:** 2 weekends.

### M3.1 Schema

```sql
create table public.meetups (
  id                    uuid primary key default gen_random_uuid(),
  host_id               uuid not null references public.profiles(id) on delete cascade,
  destination_lat       double precision not null,
  destination_lng       double precision not null,
  destination_name      text not null,
  destination_address   text,
  starts_at             timestamptz not null default now(),
  target_arrival_at     timestamptz,
  ends_at               timestamptz not null default (now() + interval '4 hours'),
  parking_buffer_min    int not null default 0,
  status                text not null default 'active' check (status in ('active', 'ended', 'cancelled')),
  share_token           text not null unique default encode(gen_random_bytes(16), 'hex'),
  category              text,
  created_at            timestamptz not null default now()
);

create index meetups_host_idx on public.meetups(host_id);
create index meetups_status_idx on public.meetups(status) where status = 'active';

create table public.meetup_participants (
  meetup_id             uuid not null references public.meetups(id) on delete cascade,
  user_id               uuid not null references public.profiles(id) on delete cascade,
  status                text not null default 'invited'
                        check (status in ('invited', 'accepted', 'declined', 'arrived')),
  joined_at             timestamptz,
  arrived_at            timestamptz,
  -- Live state (populated in M4)
  last_lat              double precision,
  last_lng              double precision,
  last_seen_at          timestamptz,
  last_accuracy_m       real,
  inferred_mode         text,
  current_eta_seconds   int,
  current_route_polyline text,
  -- Punctuality (populated in M5)
  predicted_arrival_at  timestamptz,
  punctuality_state     text,
  punctuality_changed_at timestamptz,
  primary key (meetup_id, user_id)
);

alter table public.meetups enable row level security;
alter table public.meetup_participants enable row level security;

-- A user can see meetups they host or participate in
create policy "see own meetups"
  on public.meetups for select
  using (
    auth.uid() = host_id
    or exists (select 1 from public.meetup_participants
               where meetup_id = meetups.id and user_id = auth.uid())
  );

-- Hardened in migration 20260609_meetup_host_update_policy.sql: WITH CHECK added
-- so the host edit path (e.g. editing the destination/address or the target arrival
-- time after creation) is fully covered and the host cannot reassign host_id on update.
-- The policy is row-scoped (not column-scoped), so editing target_arrival_at rides on
-- the same policy as the destination edit — no extra migration needed.
create policy "host can update meetups"
  on public.meetups for update
  using (auth.uid() = host_id)
  with check (auth.uid() = host_id);

create policy "host creates meetups"
  on public.meetups for insert
  with check (auth.uid() = host_id);

-- Hardened in migration 20260609_meetup_participant_visibility.sql: the SELECT policy
-- uses SECURITY DEFINER helpers instead of a direct self-recursive policy subquery.
-- Invited users must see the whole roster, including the host/inviter.
create or replace function public.is_meetup_participant(p_meetup_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.meetup_participants mp
    where mp.meetup_id = p_meetup_id
      and mp.user_id = p_user_id
  );
$$;

create policy participants_select
  on public.meetup_participants for select
  to authenticated
  using (
    public.is_meetup_host(meetup_id)
    or public.is_meetup_participant(meetup_id, auth.uid())
  );

create or replace function public.list_meetup_participants(p_meetup_id uuid)
returns table (
  meetup_id uuid,
  user_id uuid,
  status text,
  lat double precision,
  lng double precision,
  bearing double precision,
  eta_seconds int,
  location_updated_at timestamptz,
  display_name text,
  phone_e164 text
)
language sql
security definer
set search_path = public
as $$
  select
    mp.meetup_id,
    mp.user_id,
    mp.status,
    mp.lat,
    mp.lng,
    mp.bearing,
    mp.eta_seconds,
    mp.location_updated_at,
    p.display_name,
    p.phone_e164
  from public.meetup_participants mp
  join public.profiles p on p.id = mp.user_id
  join public.meetups m on m.id = mp.meetup_id
  where mp.meetup_id = p_meetup_id
    and (
      public.is_meetup_host(p_meetup_id)
      or public.is_meetup_participant(p_meetup_id, auth.uid())
    )
  order by
    case
      when mp.user_id = m.host_id then 0
      when mp.user_id = auth.uid() then 1
      else 2
    end,
    p.display_name;
$$;

grant execute on function public.list_meetup_participants(uuid) to authenticated;

create policy "host adds participants on create"
  on public.meetup_participants for insert
  with check (
    exists (select 1 from public.meetups
            where id = meetup_id and host_id = auth.uid())
  );

create policy "user updates own participation"
  on public.meetup_participants for update
  using (auth.uid() = user_id);
```

> **Note (friendship gate, June 2026):** The live INSERT policy has been renamed
> `participants_insert` and tightened so a host can only add an invitee who is an
> **accepted friend** (the host's own row is exempt — you are not your own friend).
> Client-side gating in `CreateMeetupView` / `AddParticipantsSheet` is bypassable, so
> this RLS policy is the real enforcement. See M2.4 below for the canonical SQL.

### M3.2 Sequence Number for WebSocket Updates (preparation for M4)

```sql
-- Each broadcast carries a monotonic seq per meetup.
alter table public.meetup_participants add column update_seq bigint not null default 0;

-- Stored procedure that all writes go through, ensuring monotonic seq
create or replace function public.update_participant_state(
  p_meetup_id uuid,
  p_user_id uuid,
  p_updates jsonb
) returns void
language plpgsql
security definer
as $$
declare
  next_seq bigint;
begin
  select coalesce(max(update_seq), 0) + 1 into next_seq
  from public.meetup_participants where meetup_id = p_meetup_id;

  update public.meetup_participants
  set
    last_lat = coalesce((p_updates->>'last_lat')::double precision, last_lat),
    last_lng = coalesce((p_updates->>'last_lng')::double precision, last_lng),
    last_seen_at = coalesce((p_updates->>'last_seen_at')::timestamptz, last_seen_at),
    last_accuracy_m = coalesce((p_updates->>'last_accuracy_m')::real, last_accuracy_m),
    inferred_mode = coalesce(p_updates->>'inferred_mode', inferred_mode),
    current_eta_seconds = coalesce((p_updates->>'current_eta_seconds')::int, current_eta_seconds),
    current_route_polyline = coalesce(p_updates->>'current_route_polyline', current_route_polyline),
    predicted_arrival_at = coalesce((p_updates->>'predicted_arrival_at')::timestamptz, predicted_arrival_at),
    punctuality_state = coalesce(p_updates->>'punctuality_state', punctuality_state),
    update_seq = next_seq
  where meetup_id = p_meetup_id and user_id = p_user_id;
end;
$$;
```

### M3.3 Meetup Creation Flow (iOS)

`CreateMeetupView.swift` — flow:
1. Search/pick destination (use `MKLocalSearch` for places, present results)
2. Time picker for `target_arrival_at` (optional; toggle "set a target time")
3. Friend picker (multi-select from accepted friends)
4. Confirm → POST to backend `/meetups` endpoint (or write directly via Supabase if RLS permits)

Use Supabase directly since RLS handles auth:

```swift
struct NewMeetupRequest {
    let destinationName: String
    let destinationAddress: String?
    let lat: Double
    let lng: Double
    let targetArrivalAt: Date?
    let parkingBufferMin: Int
    let inviteeIds: [UUID]
}

func createMeetup(_ req: NewMeetupRequest) async throws -> UUID {
    let supabase = SupabaseManager.shared.client
    guard let hostId = supabase.auth.currentUser?.id else { throw AuthError.notSignedIn }

    let meetup: [String: AnyJSON] = [
        "host_id": .string(hostId.uuidString),
        "destination_lat": .double(req.lat),
        "destination_lng": .double(req.lng),
        "destination_name": .string(req.destinationName),
        "destination_address": req.destinationAddress.map { .string($0) } ?? .null,
        "target_arrival_at": req.targetArrivalAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
        "parking_buffer_min": .integer(req.parkingBufferMin),
    ]

    let inserted: [Meetup] = try await supabase.from("meetups").insert(meetup).select().execute().value
    let meetupId = inserted[0].id

    // Insert participants (host is auto-accepted, invitees are 'invited')
    var participants: [[String: AnyJSON]] = [[
        "meetup_id": .string(meetupId.uuidString),
        "user_id": .string(hostId.uuidString),
        "status": .string("accepted"),
        "joined_at": .string(ISO8601DateFormatter().string(from: Date())),
    ]]
    for inviteeId in req.inviteeIds {
        participants.append([
            "meetup_id": .string(meetupId.uuidString),
            "user_id": .string(inviteeId.uuidString),
            "status": .string("invited"),
        ])
    }
    try await supabase.from("meetup_participants").insert(participants).execute()
    return meetupId
}
```

### M3.4 Backend Webhook for Meetup Invites

Add to `backend/main.py`:

```python
@app.post("/webhooks/participant-inserted")
async def participant_inserted(request: Request):
    payload = await request.json()
    record = payload.get("record", {})
    if record.get("status") != "invited":
        return {"ok": True}

    user_id = record["user_id"]
    meetup_id = record["meetup_id"]

    # Get meetup + host info
    meetup = supabase.table("meetups").select("*, profiles!meetups_host_id_fkey(display_name)").eq("id", meetup_id).single().execute()
    host_name = meetup.data["profiles"]["display_name"]
    dest = meetup.data["destination_name"]

    profile = supabase.table("profiles").select("apns_token").eq("id", user_id).single().execute()
    token = profile.data.get("apns_token")
    if not token:
        return {"ok": True}

    await send_apns_push(
        token=token,
        title=f"{host_name} invited you",
        body=f"Meetup at {dest}",
        data={"type": "meetup_invite", "meetup_id": meetup_id},
    )
    return {"ok": True}
```

Register the webhook in Supabase: table `meetup_participants`, event Insert.

### M3.5 Meetups List + Dashboard

`MeetupsListView.swift` — shows two sections: "Active" (status='active') and "Invited" (you're a participant with status='invited'). Tap an invited row to see details + accept/decline. Tap an active row to open the dashboard.

`MeetupDashboardView.swift` — three regions:
1. **Map** at top (MapKit `Map` view), destination pin + participant pins (no live data yet, just initials at host's location for self)
2. **Participants list** below, each as a tile:
   - Avatar / initials circle
   - Name
   - Status pill (Invited / Accepted / Declined / Arrived)
3. **Action button**: "Open in Apple Maps" (deep link to destination)

Apple Maps deep link format:
```swift
let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d")!
UIApplication.shared.open(url)
```

### M3.6 Shareable Invite Link

Backend route:

```python
@app.get("/share/{share_token}")
async def share_meetup(share_token: str):
    meetup = supabase.table("meetups").select("destination_name, target_arrival_at, status").eq("share_token", share_token).single().execute()
    if not meetup.data or meetup.data["status"] != "active":
        raise HTTPException(404)
    return {
        "destination_name": meetup.data["destination_name"],
        "target_arrival_at": meetup.data["target_arrival_at"],
        "deep_link": f"meetuptracker://meetup/share/{share_token}",
        "app_store_url": "https://apps.apple.com/...",
    }
```

iOS handles the `meetuptracker://` URL scheme via `onOpenURL` in SwiftUI to navigate into the meetup.

### M3.7 Acceptance Criteria for M3

- [ ] Host can create a meetup: pick destination via map search, optionally set target time, select multiple friends, send
- [ ] Each invitee gets a push notification: "{Host} invited you — Meetup at {place}"
- [ ] Invitee opens app, sees pending invite, can accept or decline
- [ ] After accept, host's dashboard shows them as a green-tile participant
- [ ] After decline, host's dashboard shows them as a faded-tile participant
- [ ] "Open in Apple Maps" button on dashboard opens Maps with the destination set
- [ ] Shareable link works: tapping it on a phone with the app installed opens the invite flow
- [ ] Code committed on `m3-meetups` branch

### M3.8 M3 Watch-Outs

- `MKLocalSearch` requires location authorization to be useful. Request "When In Use" before showing the destination picker.
- Time zones: target time picker should pick a time *in the user's local zone*, but stored as UTC. Use `DateFormatter` with explicit timezone settings or you'll get bugs.
- Don't let users invite themselves. Filter the friend picker.

---

## M4 — Live Location

**Goal:** Two test devices in an active meetup. Both see each other moving on the map in real time. ETAs update as you move. Reconnection after network drops works seamlessly.

**Estimated time:** 2 weekends. The hardest milestone.

### M4.1 Backend ETA Service

Create `backend/services/routing.py`:

```python
import os
import httpx
from typing import Optional

MAPBOX_TOKEN = os.environ["MAPBOX_ACCESS_TOKEN"]
MAPBOX_BASE = "https://api.mapbox.com/directions/v5/mapbox"

async def get_route(
    from_lat: float, from_lng: float,
    to_lat: float, to_lng: float,
    mode: str = "driving",  # 'driving' | 'walking' | 'cycling'
) -> Optional[dict]:
    profile_map = {"driving": "driving-traffic", "walking": "walking", "cycling": "cycling"}
    profile = profile_map.get(mode, "driving-traffic")
    url = f"{MAPBOX_BASE}/{profile}/{from_lng},{from_lat};{to_lng},{to_lat}"
    params = {
        "access_token": MAPBOX_TOKEN,
        "geometries": "polyline6",
        "alternatives": "true",
        "overview": "full",
    }
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(url, params=params)
    if r.status_code != 200:
        return None
    data = r.json()
    if not data.get("routes"):
        return None
    primary = data["routes"][0]
    alternates = data["routes"][1:3]  # up to 2 alternates
    return {
        "primary_polyline": primary["geometry"],
        "primary_duration_s": int(primary["duration"]),
        "primary_distance_m": int(primary["distance"]),
        "alternate_polylines": [r["geometry"] for r in alternates],
    }
```

### M4.2 Backend Location-Update Endpoint

Add to `backend/main.py`:

```python
from fastapi import Depends
from datetime import datetime, timezone
from services.routing import get_route
from polyline import decode as decode_polyline

@app.post("/meetups/{meetup_id}/location")
async def post_location(meetup_id: str, payload: dict, user = Depends(verify_supabase_jwt)):
    """
    payload: { lat, lng, accuracy_m, speed_mps, heading_deg, mode, ts }
    """
    user_id = user["sub"]

    # Reject low-accuracy fixes for ETA computation
    accuracy = payload.get("accuracy_m", 9999)
    if accuracy > 100:
        # Still record the position but don't recompute ETA
        await record_position_only(meetup_id, user_id, payload)
        return {"ok": True, "note": "low_accuracy"}

    # Get destination + cached route
    meetup = supabase.table("meetups").select("destination_lat, destination_lng, parking_buffer_min").eq("id", meetup_id).single().execute()
    if not meetup.data:
        raise HTTPException(404)

    dest_lat = meetup.data["destination_lat"]
    dest_lng = meetup.data["destination_lng"]
    buffer_min = meetup.data["parking_buffer_min"]

    # Compute route + ETA
    route = await get_route(payload["lat"], payload["lng"], dest_lat, dest_lng, payload.get("mode", "driving"))
    if route:
        eta_s = route["primary_duration_s"] + buffer_min * 60

        # Mark arrived if within 50m
        from math import radians, cos, sin, asin, sqrt
        def haversine(lat1, lng1, lat2, lng2):
            R = 6371000
            dlat = radians(lat2 - lat1)
            dlng = radians(lng2 - lng1)
            a = sin(dlat/2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng/2)**2
            return 2 * R * asin(sqrt(a))

        distance_to_dest = haversine(payload["lat"], payload["lng"], dest_lat, dest_lng)
        is_arrived = distance_to_dest < 50

        update_data = {
            "last_lat": payload["lat"],
            "last_lng": payload["lng"],
            "last_seen_at": datetime.now(timezone.utc).isoformat(),
            "last_accuracy_m": accuracy,
            "inferred_mode": payload.get("mode"),
            "current_eta_seconds": eta_s,
            "current_route_polyline": route["primary_polyline"],
        }
        if is_arrived:
            update_data["status"] = "arrived"
            update_data["arrived_at"] = datetime.now(timezone.utc).isoformat()

        supabase.rpc("update_participant_state", {
            "p_meetup_id": meetup_id,
            "p_user_id": user_id,
            "p_updates": update_data,
        }).execute()

    return {"ok": True}
```

### M4.3 iOS Location Manager

Create `MeetupTracker/Services/LocationManager.swift`:

```swift
import CoreLocation
import CoreMotion

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private(set) var activeMeetupId: UUID?
    private var lastUploadedLocation: CLLocation?
    private var lastUploadAt: Date?

    @Published var currentMode: String = "stationary"

    override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking(meetupId: UUID) {
        activeMeetupId = meetupId
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20  // meters
        manager.startUpdatingLocation()
        startMotionUpdates()
    }

    func stopTracking() {
        activeMeetupId = nil
        manager.stopUpdatingLocation()
        motionManager.stopActivityUpdates()
    }

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity = activity else { return }
            if activity.automotive { self?.currentMode = "driving" }
            else if activity.walking || activity.running { self?.currentMode = "walking" }
            else if activity.cycling { self?.currentMode = "cycling" }
            else if activity.stationary { self?.currentMode = "stationary" }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let meetupId = activeMeetupId else { return }

        // Throttle: only upload if moved >20m or >30s elapsed
        let now = Date()
        if let last = lastUploadedLocation, let lastUp = lastUploadAt,
           location.distance(from: last) < 20, now.timeIntervalSince(lastUp) < 30 {
            return
        }
        lastUploadedLocation = location
        lastUploadAt = now

        Task { await uploadLocation(location, meetupId: meetupId) }
    }

    private func uploadLocation(_ location: CLLocation, meetupId: UUID) async {
        let payload: [String: Any] = [
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude,
            "accuracy_m": location.horizontalAccuracy,
            "speed_mps": max(0, location.speed),
            "heading_deg": location.course,
            "mode": currentMode,
            "ts": ISO8601DateFormatter().string(from: location.timestamp),
        ]

        guard let url = URL(string: "\(BACKEND_URL)/meetups/\(meetupId)/location"),
              let token = try? await SupabaseManager.shared.client.auth.session.accessToken
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _ = try? await URLSession.shared.data(for: request)
    }
}
```

### M4.4 Realtime Subscription on Dashboard

In `MeetupDashboardView.swift`, subscribe to participant changes:

```swift
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var participants: [Participant] = []
    private var channel: RealtimeChannelV2?

    func startSubscription(meetupId: UUID) {
        Task {
            // 1. Snapshot first
            await loadSnapshot(meetupId: meetupId)

            // 2. Subscribe to live updates
            let supabase = SupabaseManager.shared.client
            let ch = supabase.realtimeV2.channel("meetup-\(meetupId)")
            await ch.onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "meetup_participants",
                filter: "meetup_id=eq.\(meetupId.uuidString)"
            ) { [weak self] action in
                Task { @MainActor in
                    await self?.applyChange(action)
                }
            }
            try? await ch.subscribe()
            channel = ch
        }
    }

    func stopSubscription() {
        Task { try? await channel?.unsubscribe() }
    }

    private func loadSnapshot(meetupId: UUID) async {
        // GET full state from Supabase or backend snapshot endpoint
    }

    private func applyChange(_ action: AnyAction) async {
        // Parse the action, find the participant, update or insert
    }
}
```

### M4.5 Snapshot Endpoint (for reconnect)

```python
@app.get("/meetups/{meetup_id}/snapshot")
async def snapshot(meetup_id: str, user = Depends(verify_supabase_jwt)):
    # Verify user is part of the meetup
    p = supabase.table("meetup_participants").select("*").eq("meetup_id", meetup_id).execute()
    return {"participants": p.data, "snapshot_at": datetime.now(timezone.utc).isoformat()}
```

iOS calls this on:
- Dashboard open
- Realtime channel reconnect (which Supabase signals via channel state changes)
- App returning from background after >30s

### M4.6 Battery and Background

When the dashboard view appears AND the user is a participant of an active meetup:
1. Check location permission. If only "When In Use", prompt for "Always" with explanation.
2. Call `LocationManager.shared.startTracking(meetupId:)`

When the meetup ends or the user leaves the meetup:
1. Call `LocationManager.shared.stopTracking()`

When the participant is `arrived`:
1. Stop tracking automatically (saves battery).

### M4.7 Acceptance Criteria for M4

- [ ] Two devices in an active meetup both see each other's positions on the map updating in real time
- [ ] ETA shows on each tile and updates as participants move
- [ ] Putting one device in airplane mode for 60s, then turning it back on: dashboard recovers cleanly via snapshot+resume
- [ ] Closing the app on one device: location continues to update for the other for at least 5 minutes (background location works)
- [ ] When a participant arrives within 50m, their tile updates to "Arrived" and their location stops being tracked
- [ ] Battery drain during a 30-min active meetup is <5% on the tracking device
- [ ] Code committed on `m4-live-location` branch

### M4.8 M4 Watch-Outs

- iOS will *kill* your background location updates if you don't actually use the data. Make sure you're getting the delegate callbacks even when backgrounded.
- "Always" permission must be requested AFTER "When In Use" has been granted, and only when contextually justified. Apple reviewers test this.
- Mapbox Directions is rate-limited. Cache routes per (origin-grid, destination) pair for ~60s in the backend.
- The first location fix on iPhone takes 2–10 seconds. Show a "Locating..." state on the dashboard.

---

## M5 — Punctuality + Smart Notifications

**Goal:** During an active meetup with a target time, dashboard tiles are color-coded by punctuality. Late participants trigger push notifications to the host. "Leave by" notifications fire to participants who haven't started.

**Estimated time:** 1 weekend.

### M5.0 Supabase Edge Functions + DB Triggers (Push Delivery)

Three Edge Functions live in `supabase/functions/`. They are deployed via:

```bash
supabase functions deploy push-meetup-invite
supabase functions deploy push-meetup-status
supabase functions deploy push-meetup-cancelled
supabase functions deploy push-friend-request
```

Required secrets (set once per project):

```bash
supabase secrets set APPLE_TEAM_ID=<your 10-char team ID>
supabase secrets set APNS_KEY_ID=<10-char key ID from Apple Developer>
supabase secrets set APNS_AUTH_KEY="$(cat /path/to/AuthKey_XXXX.p8)"
supabase secrets set APNS_USE_SANDBOX=true   # true for dev/TestFlight, false for prod
```

The shared APNs helper lives in `supabase/functions/_shared/apns.ts`. It handles JWT signing (ES256), APNs host switching, single retry on 5xx, and clearing stale tokens on 410.

#### DB Triggers

Apply these in the Supabase SQL editor after deploying the functions. Replace `<project-ref>` with `boyrqhbdkqzffvfokpri`.

```sql
-- Enable pg_net extension (only needed once per project)
create extension if not exists pg_net;

-- 1. Meetup invite push: fires when a participant row is inserted with status='invited'
create or replace function notify_meetup_invite()
returns trigger language plpgsql as $$
begin
  if new.status = 'invited' then
    perform pg_net.http_post(
      url := 'https://<project-ref>.supabase.co/functions/v1/push-meetup-invite',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
      ),
      body := jsonb_build_object('participantId', new.id)
    );
  end if;
  return new;
end;
$$;

create or replace trigger trg_meetup_invite
  after insert on meetup_participants
  for each row execute function notify_meetup_invite();

-- 2. Meetup status push: fires when participant status changes to accepted/declined/arrived
create or replace function notify_meetup_status()
returns trigger language plpgsql as $$
begin
  if old.status is distinct from new.status
     and new.status in ('accepted', 'declined', 'arrived') then
    perform pg_net.http_post(
      url := 'https://<project-ref>.supabase.co/functions/v1/push-meetup-status',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
      ),
      body := jsonb_build_object('participantId', new.id, 'newStatus', new.status)
    );
  end if;
  return new;
end;
$$;

create or replace trigger trg_meetup_status
  after update on meetup_participants
  for each row execute function notify_meetup_status();

-- 3. Friend request push: fires on new friendship row or acceptance
create or replace function notify_friendship()
returns trigger language plpgsql as $$
begin
  if TG_OP = 'INSERT' and new.status = 'pending' then
    perform pg_net.http_post(
      url := 'https://<project-ref>.supabase.co/functions/v1/push-friend-request',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
      ),
      body := jsonb_build_object('friendshipId', new.id, 'event', 'friend_request')
    );
  elsif TG_OP = 'UPDATE' and old.status = 'pending' and new.status = 'accepted' then
    perform pg_net.http_post(
      url := 'https://<project-ref>.supabase.co/functions/v1/push-friend-request',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
      ),
      body := jsonb_build_object('friendshipId', new.id, 'event', 'friend_accepted')
    );
  end if;
  return new;
end;
$$;

create or replace trigger trg_friendship_push
  after insert or update on friendships
  for each row execute function notify_friendship();
```

> **Note:** `current_setting('app.service_role_key', true)` requires the service role key to be set as a Postgres config var: `alter database postgres set app.service_role_key = '<key>';` — or replace with a hardcoded value during initial setup and rotate to the config var approach before prod.

> **Live trigger wiring:** the documentation above reflects the original design. The triggers that are actually applied live in `supabase/migrations/20260609_push_triggers.sql`, which route through the `public.call_push_function(fn, payload)` helper and read the service-role key from Supabase Vault (`vault.decrypted_secrets where name = 'service_role_key'`) instead of `current_setting`. New push triggers should follow that pattern.

#### Meetup cancelled push (`push-meetup-cancelled`)

When a host cancels a meetup, every still-engaged participant gets a push telling them the event was cancelled (meetup title in the body). Edge function: `supabase/functions/push-meetup-cancelled/index.ts`. Trigger: `supabase/migrations/20260609_cancel_meetup_push.sql`.

- **Trigger:** `trg_notify_meetup_cancelled` — `AFTER UPDATE ON public.meetups`, fires `public.notify_meetup_cancelled()` only when `new.status = 'cancelled' AND old.status IS DISTINCT FROM 'cancelled'`. Auto-expiry sets status to `'ended'`, so it never fires this push.
- **Payload:** `{ meetupId }`.
- **Recipients:** all `meetup_participants` for the meetup with status in (`invited`, `accepted`, `arrived`), excluding the host (who performed the cancellation). `declined` participants are skipped.
- **Notification:** title `Meetup cancelled`, body `<destination_name> has been cancelled`, `event: meetup_cancelled`, `meetupId` for deep-linking.
- The iOS cancel flow is unchanged: `MeetupService.cancelMeetup(meetupId:)` already updates `meetups.status` to `'cancelled'`, which is what the trigger keys off of.

### M5.1 Punctuality Computation (Backend)

Add to `backend/services/punctuality.py`:

```python
from datetime import datetime, timedelta, timezone
from enum import Enum

class State(str, Enum):
    UNKNOWN = "unknown"
    EARLY = "early"
    ON_TIME = "on_time"
    CUTTING_CLOSE = "cutting_close"
    LATE = "late"
    VERY_LATE = "very_late"
    ARRIVED = "arrived"

THRESHOLDS_MIN = [(-5, State.EARLY), (2, State.ON_TIME), (5, State.CUTTING_CLOSE), (15, State.LATE)]
HYSTERESIS_BUFFER_MIN = 2
STATE_HOLD_SECONDS = 60

def classify(delta_min: float) -> State:
    if delta_min <= -5: return State.EARLY
    if delta_min <= 2: return State.ON_TIME
    if delta_min <= 5: return State.CUTTING_CLOSE
    if delta_min <= 15: return State.LATE
    return State.VERY_LATE

def crossed_with_buffer(current: State, proposed: State, delta_min: float) -> bool:
    """Only allow state change if past threshold by buffer amount."""
    order = [State.EARLY, State.ON_TIME, State.CUTTING_CLOSE, State.LATE, State.VERY_LATE]
    if current not in order or proposed not in order:
        return True  # any → into ordered band: allow
    cur_i = order.index(current)
    prop_i = order.index(proposed)
    if prop_i > cur_i:
        # Getting later: need to clearly cross next threshold
        threshold = [(-5, 2), (2, 5), (5, 15), (15, 999)][cur_i][1]
        return delta_min > threshold + HYSTERESIS_BUFFER_MIN
    if prop_i < cur_i:
        # Getting earlier: need to clearly drop below current band's lower threshold
        threshold = [(-5, 2), (2, 5), (5, 15), (15, 999)][cur_i][0]
        return delta_min < threshold - HYSTERESIS_BUFFER_MIN
    return False

async def update_punctuality(participant: dict, meetup: dict, now: datetime):
    target = meetup.get("target_arrival_at")
    if not target:
        return None
    target_dt = datetime.fromisoformat(target.replace("Z", "+00:00"))

    eta_s = participant.get("current_eta_seconds")
    if eta_s is None:
        proposed = State.UNKNOWN
        delta_min = 0
    elif participant.get("status") == "arrived":
        proposed = State.ARRIVED
        delta_min = 0
    else:
        predicted = now + timedelta(seconds=eta_s)
        delta_min = (predicted - target_dt).total_seconds() / 60
        proposed = classify(delta_min)

    current = State(participant.get("punctuality_state") or "unknown")
    if proposed == current:
        return None

    # Hysteresis
    if not crossed_with_buffer(current, proposed, delta_min):
        return None
    last_change = participant.get("punctuality_changed_at")
    if last_change and current != State.UNKNOWN:
        last_dt = datetime.fromisoformat(last_change.replace("Z", "+00:00"))
        if (now - last_dt).total_seconds() < STATE_HOLD_SECONDS:
            return None

    return {
        "punctuality_state": proposed.value,
        "predicted_arrival_at": (now + timedelta(seconds=eta_s)).isoformat() if eta_s else None,
        "punctuality_changed_at": now.isoformat(),
        "_minutes_late": int(delta_min),
        "_should_notify": should_notify(current, proposed),
    }

def should_notify(prev: State, new: State) -> bool:
    notify_on = {State.LATE, State.VERY_LATE}
    return new in notify_on and prev not in notify_on or (prev in notify_on and new == State.ON_TIME)
```

Call `update_punctuality` from the location-update endpoint after computing ETA. If `_should_notify`, push to host.

### M5.2 Smart "Leave By" Cron

Run every 60 seconds (use `apscheduler` or a separate worker process):

```python
from apscheduler.schedulers.asyncio import AsyncIOScheduler

async def leave_by_tick():
    """For each active meetup with a target time, check participants
    who haven't started and notify them when leave time approaches."""
    now = datetime.now(timezone.utc)
    meetups = supabase.table("meetups").select("*").eq("status", "active").execute()
    for m in meetups.data:
        target = m.get("target_arrival_at")
        if not target: continue
        target_dt = datetime.fromisoformat(target.replace("Z", "+00:00"))

        participants = supabase.table("meetup_participants").select("*, profiles(apns_token, last_lat, last_lng)").eq("meetup_id", m["id"]).execute()
        for p in participants.data:
            if p.get("status") != "accepted": continue  # only those who said yes but haven't started
            if p.get("last_seen_at"): continue  # already moving
            # Compute ETA from last known location
            last_lat = p.get("last_lat") or p["profiles"].get("last_lat")
            last_lng = p.get("last_lng") or p["profiles"].get("last_lng")
            if not last_lat: continue

            route = await get_route(last_lat, last_lng, m["destination_lat"], m["destination_lng"], "driving")
            if not route: continue
            eta_s = route["primary_duration_s"] + m["parking_buffer_min"] * 60
            should_leave_at = target_dt - timedelta(seconds=eta_s)
            minutes_until_leave = (should_leave_at - now).total_seconds() / 60

            if 4 < minutes_until_leave <= 5:
                await send_apns_push(
                    token=p["profiles"]["apns_token"],
                    title="Time to head out soon",
                    body=f"Leave in 5 min to make it to {m['destination_name']} by {target_dt.strftime('%-I:%M %p')}.",
                    data={"type": "leave_soon", "meetup_id": m["id"]},
                )
            elif -1 < minutes_until_leave <= 0:
                await send_apns_push(
                    token=p["profiles"]["apns_token"],
                    title="Leave now",
                    body=f"Head to {m['destination_name']} now to arrive on time.",
                    data={"type": "leave_now", "meetup_id": m["id"]},
                )

scheduler = AsyncIOScheduler()
scheduler.add_job(leave_by_tick, "interval", seconds=60)
scheduler.start()
```

### M5.3 iOS Tile Coloring

Update `ParticipantTileView`:

```swift
struct ParticipantTileView: View {
    let participant: Participant

    var stateColor: Color {
        switch participant.punctualityState {
        case "early": return .blue
        case "on_time": return .green
        case "cutting_close": return .yellow
        case "late": return .orange
        case "very_late": return .red
        case "arrived": return .green
        default: return .gray
        }
    }

    var stateLabel: String {
        guard let minutes = participant.minutesLate else { return statusLabel(for: participant.status) }
        if minutes > 0 { return "\(minutes) min late" }
        if minutes < 0 { return "\(-minutes) min early" }
        return "On time"
    }

    var body: some View {
        HStack {
            Circle().fill(stateColor).frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(participant.displayName).font(.headline)
                Text(stateLabel).font(.subheadline).foregroundStyle(stateColor)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(formatETA(participant.etaSeconds)).font(.title3.monospacedDigit())
                Text(modeIcon(participant.inferredMode))
            }
        }
        .padding()
        .background(stateColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stateColor, lineWidth: 0).fill(.clear))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(Rectangle().fill(stateColor).frame(width: 4), alignment: .leading)
    }
}
```

Sort the participant list by punctuality priority:

```swift
let priority: [String: Int] = [
    "very_late": 0, "late": 1, "cutting_close": 2,
    "on_time": 3, "early": 4, "arrived": 5, "unknown": 6
]
participants.sorted { (priority[$0.punctualityState ?? "unknown"] ?? 6) < (priority[$1.punctualityState ?? "unknown"] ?? 6) }
```

### M5.4 Acceptance Criteria for M5

- [ ] Active meetup with target time set: tiles are colored by punctuality
- [ ] Hysteresis works: jiggling at the threshold doesn't flicker the tile
- [ ] When a participant becomes "late," host receives push: "Sarah will be 8 min late"
- [ ] When the same participant recovers to "on_time," host receives recovery push
- [ ] 5 minutes before they need to leave, participants receive "Leave in 5 min" push
- [ ] At "leave now" time, participants receive a second push
- [ ] Code committed on `m5-punctuality` branch

---

## M6 — Polish, Privacy, Live Activities

**Goal:** App feels native and shippable. Privacy controls are end-to-end. Lock screen shows live meetup status.

**Estimated time:** 1–2 weekends.

### M6.1 Privacy Controls

- [ ] Persistent banner during active meetup: "Sharing location with {meetup name}. Tap to stop." Tappable to end participation.
- [ ] Settings → Activity log: list of every meetup, when joined, when sharing ended, who saw your location.
- [ ] Block user flow: from a friend's profile, tap Block → confirmation → friendship status → 'blocked', participant rows in shared meetups force-ended.
- [ ] Audit log table:

```sql
create table public.audit_log (
  id              bigserial primary key,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  event           text not null,
  meetup_id       uuid references public.meetups(id) on delete set null,
  metadata        jsonb,
  created_at      timestamptz not null default now()
);

alter table public.audit_log enable row level security;
create policy "users see their own audit log"
  on public.audit_log for select using (auth.uid() = user_id);
```

Backend writes to this on key events: meetup joined, location sharing started/ended, participant viewed your location (optional), blocked.

### M6.2 Live Activities

Create a Widget Extension target. Define the activity attributes:

```swift
import ActivityKit

struct MeetupActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var participantSummaries: [ParticipantSummary]
        var earliestArrival: Date?
    }

    public struct ParticipantSummary: Codable, Hashable, Identifiable {
        public var id: String
        var name: String
        var etaMinutes: Int?
        var state: String  // "on_time", "late", etc.
    }

    var meetupName: String
    var targetArrivalAt: Date?
}
```

Start the Live Activity when the user enters dashboard:

```swift
let attributes = MeetupActivityAttributes(meetupName: meetup.destinationName, targetArrivalAt: meetup.targetArrivalAt)
let initialContent = MeetupActivityAttributes.ContentState(participantSummaries: [...], earliestArrival: ...)
let activity = try Activity.request(attributes: attributes, content: .init(state: initialContent, staleDate: nil))
```

Update on participant changes. End on meetup end.

### M6.3 Acceptance Criteria for M6

- [ ] Active meetup banner is always visible while sharing; tap stops sharing
- [ ] Activity log shows full history
- [ ] Block user works end-to-end
- [ ] Lock screen shows Live Activity during active meetup
- [ ] Dynamic Island shows meetup status (on supported devices)
- [ ] Code committed on `m6-polish` branch

---

## M7 — TestFlight & Real Use

- [ ] App Store Connect listing created (description, screenshots, privacy details)
- [ ] App uploaded to TestFlight
- [ ] 5–10 friends added as testers
- [ ] Run at least 20 real meetups
- [ ] Bugs filed and fixed
- [ ] Battery drain measured under typical use; tune update intervals if needed
- [ ] Edge cases addressed: poor GPS in parking garages, last-minute declines, host leaves early

---

## M8 — Mapbox Navigation SDK (v2, Post-Launch)

Defer until v1 is shipping smoothly.

### Steps

1. Mapbox account → upgrade to navigation-enabled (still free under MAU cap)
2. Add `MapboxNavigationCore` and `MapboxNavigationUIKit` Swift Package dependencies
3. Replace "Open in Apple Maps" button with "Start Navigation" → present `NavigationViewController`
4. Configure voice controller with `RouteVoiceController` (uses Mapbox Voice API by default; falls back to AVSpeechSynthesizer)
5. Test in real-world driving (don't test by simulating; voice timing matters)

---

## Bill Splitting Tables

Run all SQL below in the Supabase SQL editor before using any bill-splitting features on the client.

```sql
-- ============================================================
-- Bill Splitting Tables (run in Supabase SQL editor)
-- ============================================================

-- Bills: one per meetup
CREATE TABLE bills (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meetup_id    uuid NOT NULL REFERENCES meetups(id) ON DELETE CASCADE,
  created_by   uuid NOT NULL REFERENCES profiles(id),
  subtotal     numeric(10,2) NOT NULL,
  tax          numeric(10,2) NOT NULL DEFAULT 0,
  tip          numeric(10,2) NOT NULL DEFAULT 0,
  total        numeric(10,2) NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (meetup_id)
);

-- Line items parsed from receipt
CREATE TABLE bill_items (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_id  uuid NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
  name     text NOT NULL,
  price    numeric(10,2) NOT NULL,
  position int NOT NULL
);

-- Which user claimed which item
CREATE TABLE bill_item_claims (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_item_id uuid NOT NULL REFERENCES bill_items(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES profiles(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (bill_item_id, user_id)
);

-- RLS
ALTER TABLE bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_item_claims ENABLE ROW LEVEL SECURITY;

CREATE POLICY "meetup participants can read bills"
  ON bills FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM meetup_participants
    WHERE meetup_participants.meetup_id = bills.meetup_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "meetup participants can insert bills"
  ON bills FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM meetup_participants
    WHERE meetup_participants.meetup_id = bills.meetup_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "meetup participants can read bill_items"
  ON bill_items FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM bills
    JOIN meetup_participants ON meetup_participants.meetup_id = bills.meetup_id
    WHERE bills.id = bill_items.bill_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "meetup participants can insert bill_items"
  ON bill_items FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM bills
    JOIN meetup_participants ON meetup_participants.meetup_id = bills.meetup_id
    WHERE bills.id = bill_items.bill_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "meetup participants can update bill_items"
  ON bill_items FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM bills
    JOIN meetup_participants ON meetup_participants.meetup_id = bills.meetup_id
    WHERE bills.id = bill_items.bill_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "meetup participants can read claims"
  ON bill_item_claims FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM bill_items
    JOIN bills ON bills.id = bill_items.bill_id
    JOIN meetup_participants ON meetup_participants.meetup_id = bills.meetup_id
    WHERE bill_items.id = bill_item_claims.bill_item_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "users can insert own claims"
  ON bill_item_claims FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "users can delete own claims"
  ON bill_item_claims FOR DELETE
  USING (user_id = auth.uid());
```

---

## Multi-Receipt Bill Splitting Migration

Run after the bill splitting tables above. Adds a `receipts` table (one per place per meetup) and makes `bill_items.bill_id` nullable so items can belong to a receipt instead.

```sql
-- ============================================================
-- Multi-Receipt Bill Splitting (run in Supabase SQL editor)
-- ============================================================

-- One receipt per place visited during a meetup
CREATE TABLE receipts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meetup_id     uuid NOT NULL REFERENCES meetups(id) ON DELETE CASCADE,
  place_name    text NOT NULL,
  payer_user_id uuid NOT NULL REFERENCES auth.users(id),
  total_amount  numeric(10,2) NOT NULL DEFAULT 0,
  photo_url     text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Allow bill_items to belong to a receipt (makes bill_id nullable)
ALTER TABLE bill_items ALTER COLUMN bill_id DROP NOT NULL;
ALTER TABLE bill_items ADD COLUMN IF NOT EXISTS receipt_id uuid REFERENCES receipts(id) ON DELETE CASCADE;

-- RLS for receipts
ALTER TABLE receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "participants can read receipts"
  ON receipts FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM meetup_participants
    WHERE meetup_participants.meetup_id = receipts.meetup_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "participants can insert receipts"
  ON receipts FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM meetup_participants
    WHERE meetup_participants.meetup_id = receipts.meetup_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "participants can update receipts"
  ON receipts FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM meetup_participants
    WHERE meetup_participants.meetup_id = receipts.meetup_id
      AND meetup_participants.user_id = auth.uid()
  ));

-- Update bill_items RLS policies to also allow access via receipt_id
-- (existing policies check bill_id; add receipt-based policies alongside them)

CREATE POLICY "participants can read receipt items"
  ON bill_items FOR SELECT
  USING (
    receipt_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM receipts
      JOIN meetup_participants ON meetup_participants.meetup_id = receipts.meetup_id
      WHERE receipts.id = bill_items.receipt_id
        AND meetup_participants.user_id = auth.uid()
    )
  );

CREATE POLICY "participants can insert receipt items"
  ON bill_items FOR INSERT
  WITH CHECK (
    receipt_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM receipts
      JOIN meetup_participants ON meetup_participants.meetup_id = receipts.meetup_id
      WHERE receipts.id = bill_items.receipt_id
        AND meetup_participants.user_id = auth.uid()
    )
  );

-- Update claims RLS to also cover receipt-linked items
CREATE POLICY "participants can read receipt item claims"
  ON bill_item_claims FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM bill_items
    JOIN receipts ON receipts.id = bill_items.receipt_id
    JOIN meetup_participants ON meetup_participants.meetup_id = receipts.meetup_id
    WHERE bill_items.id = bill_item_claims.bill_item_id
      AND meetup_participants.user_id = auth.uid()
  ));

-- Storage buckets (create via Supabase dashboard: Storage → New bucket)
-- Bucket name: receipts   — private, RLS-protected
-- Bucket name: meetup-photos — private, signed-URL access (see 20260605_meetup_photos.sql)

-- Storage RLS for receipts bucket
-- In Supabase dashboard: Storage → Policies → receipts bucket
-- INSERT policy:
--   (SELECT EXISTS (
--     SELECT 1 FROM receipts r
--     JOIN meetup_participants mp ON mp.meetup_id = r.meetup_id
--     WHERE r.id::text = (storage.foldername(name))[1]
--       AND mp.user_id = auth.uid()
--   ))
-- SELECT policy: same condition
```

---

## Appendix A — Backend Authentication Helper

Used in all protected endpoints:

```python
import jwt
from fastapi import Header, HTTPException
import httpx

async def verify_supabase_jwt(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(401)
    token = authorization[7:]
    try:
        # Supabase tokens are signed with HS256 using the JWT secret from Project Settings → API
        payload = jwt.decode(token, os.environ["SUPABASE_JWT_SECRET"], algorithms=["HS256"], audience="authenticated")
        return payload
    except jwt.PyJWTError:
        raise HTTPException(401)
```

## Appendix B — Deployment

For dev: `uvicorn main:app --reload --port 8000` + `ngrok http 8000`.

For TestFlight phase: deploy backend to Fly.io:

```bash
brew install flyctl
fly auth signup
cd backend
fly launch  # follow prompts; choose Python detection
fly secrets set SUPABASE_URL=... SUPABASE_SERVICE_KEY=... MAPBOX_ACCESS_TOKEN=... APPLE_TEAM_ID=... APPLE_BUNDLE_ID=... APNS_KEY_ID=... SUPABASE_JWT_SECRET=...
# Mount the APNs .p8 as a secret file
fly deploy
```

Update Supabase webhooks and iOS `BACKEND_URL` to the Fly URL.

## M9 — Settings (User Preferences + Account)

Expanded Settings screen (`Views/SettingsView.swift`): ACCOUNT (edit display name, delete account, sign out), APPEARANCE/ACCESSIBILITY (existing, UserDefaults via `AppSettings`), NOTIFICATIONS + PRIVACY (persisted to Supabase via `user_settings`), and ABOUT (bundle version, Terms/Support links).

### M9.1 Schema — `user_settings`

One row per user, keyed by `user_id = auth.uid()`. Notification + privacy preferences. Run in the Supabase SQL editor:

```sql
create table public.user_settings (
  user_id                     uuid primary key references public.profiles(id) on delete cascade,
  push_notifications_enabled  boolean not null default true,
  event_cancelled_enabled     boolean not null default true,
  location_sharing_enabled    boolean not null default true,
  updated_at                  timestamptz not null default now()
);

alter table public.user_settings enable row level security;

create policy "users can read their own settings"
  on public.user_settings for select
  using (auth.uid() = user_id);

create policy "users can insert their own settings"
  on public.user_settings for insert
  with check (auth.uid() = user_id);

create policy "users can update their own settings"
  on public.user_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

The iOS client upserts on `user_id` (`UserSettingsService.save`). `location_sharing_enabled` is mirrored into `UserDefaults` so `MeetupDashboardView` / `LocationManager` can gate live tracking synchronously. The `event_cancelled_enabled` flag is the gate the `feature/cancel-event-push-notifications` branch should read before sending a cancel push (the push backend should `select` this column for the recipient and skip if false).

### M9.2 Account deactivation (soft delete)

`profiles` gains a `deactivated_at` column plus a `security definer` RPC so a user can deactivate their own account without exposing service-role keys. Run:

```sql
alter table public.profiles
  add column if not exists deactivated_at timestamptz;

create or replace function public.deactivate_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set deactivated_at = now(),
         updated_at = now()
   where id = auth.uid();
end;
$$;

revoke all on function public.deactivate_account() from public;
grant execute on function public.deactivate_account() to authenticated;
```

`AuthViewModel.deactivateAndSignOut()` calls the RPC then signs out.

**Placeholder / follow-up (not built in this MVP):** a *hard* delete of the `auth.users` row requires the service-role key and must run server-side. Implement later as a Supabase Edge Function (e.g. `delete-account`) that authenticates the caller's JWT, then calls `auth.admin.deleteUser(uid)` with the service-role key held in the function's secrets — never shipped in the app. The current build does a soft deactivate + sign out.

### M9.3 Friend direct messages

Direct messages are 1:1 conversations between accepted friends. The canonical migration is `supabase/migrations/20260609_direct_messages.sql`; run it in Supabase before shipping the iOS UI. Message reactions are added by `supabase/migrations/20260610153000_message_reactions.sql`, friend profile recap stats are added by `supabase/migrations/20260610153500_friend_profile_stats.sql`, and sender-only message edits are added by `supabase/migrations/20260610154000_edit_direct_messages.sql`.

Schema:

- `conversations`: one canonical row per friend pair (`user_a_id < user_b_id`), with `last_message_at`, `last_read_a`, and `last_read_b`.
- `messages`: text and/or image messages with `conversation_id`, `sender_id`, `body`, `image_path`, `created_at`, and `edited_at`.
- `message_reactions`: emoji reactions keyed by `message_id`, `user_id`, and `emoji`, with one row per user's reaction.
- `message-photos` storage bucket: private bucket for DM images, stored at `<conversation_id>/<uuid>.jpg` and read through signed URLs.

RPCs:

- `get_or_create_conversation(p_other_user_id uuid)`: returns the existing accepted-friend conversation or creates one.
- `list_conversation_summaries()`: inbox feed with the other participant, last message preview, and unread count.
- `mark_conversation_read(p_conversation_id uuid)`: updates the caller's read timestamp.
- `list_message_reactions(p_conversation_id uuid)`: returns per-message emoji counts and whether the caller reacted.
- `toggle_message_reaction(p_message_id uuid, p_emoji text)`: adds or removes the caller's reaction for one message.
- `get_friend_profile_stats(p_profile_id uuid)`: returns attended event count plus on-time and late counts for the caller or an accepted friend.

RLS:

- Conversation reads/inserts/updates are limited to participants and accepted friends.
- Message reads/sends are limited to accepted friends in the conversation.
- Message edits are limited to the sender of the message.
- Message deletes are limited to the sender of the message.
- Reaction reads/writes are limited to accepted friends in the conversation, and deletes are limited to the user who reacted.
- Storage object read/upload/delete policies are scoped to conversation participants by the first storage path segment.

Push:

- `push-new-message` is called by the `trg_on_new_message` database trigger and sends `event: new_message`, `conversationId`, and `senderId` through APNs.

### M9.4 Profile photos

Users can upload a profile photo from Settings. The canonical migration is
`supabase/migrations/20260610030500_profile_photos.sql`.

Schema/storage:

- `profiles.avatar_url text`: stores the current public profile-photo URL.
- `profile-photos` storage bucket: public-read bucket for avatar images, stored under
  `<user_id>/<uuid>.jpg`.

RLS:

- Profile row updates still use the existing `profiles` own-row update policy.
- Accepted friends can read each other's profile rows, including `avatar_url`.
- Storage object uploads/updates/deletes are limited to the signed-in user's own folder.
- Storage object reads are public so `AsyncImage` can render avatars without signed URL churn.

iOS:

- `ProfilePhotoService` resizes and uploads the selected image.
- `AuthViewModel.updateProfilePhoto(_:)` writes `avatar_url` and updates the cached profile.
- `ProfileAvatarView` renders uploaded photos with initials as fallback across Settings,
  People, DMs, meetup creation/invites, and meetup dashboard participants.

### M9.5 Meetup photo gallery

Participants share photos during a meetup (dashboard camera button + thumbnail strip)
and afterwards in the recap (grid card). Base schema is
`supabase/migrations/20260605020000_meetup_photos.sql`; deletion + storage policies are
`supabase/migrations/20260611160000_meetup_photos_delete_and_storage.sql`.

Schema/storage:

- `meetup_photos (id, meetup_id, uploader_user_id, photo_url, caption, created_at)`:
  one row per uploaded photo. `photo_url` stores the storage path (legacy rows may hold
  a signed URL; `MeetupPhotoService.storagePath(from:)` normalizes both).
- `meetup-photos` storage bucket: private, files at `<meetup_id>/<uuid>.jpg`, read via
  1-hour signed URLs regenerated on each fetch.

RLS (table):

- SELECT: any participant of the meetup.
- INSERT: own row only, and the uploader must be the host or an *active* participant —
  `is_active_meetup_participant()` checks `status in ('accepted', 'arrived', 'yes')`,
  so invited/declined users cannot post.
- DELETE: the uploader or the meetup host.

RLS (storage.objects, scoped by the `<meetup_id>/` path prefix):

- SELECT: host or participant of the path's meetup.
- INSERT: host or active participant of the path's meetup.
- DELETE: object owner (uploader) or the path's meetup host.

iOS:

- `MeetupPhotoService` uploads (JPEG 0.8), inserts rows, fetches with signed-URL refresh,
  and deletes (`deletePhoto` removes the row, then best-effort removes the storage object).
  `canDelete(photo:currentUserId:meetupHostId:)` mirrors the delete policy for UI gating.
- `MeetupPhotoPagerView` is the shared full-screen swipeable viewer (TabView pager) with
  share and delete, presented from both the dashboard strip and the recap grid.
- `MeetupDashboardView` keeps a realtime subscription on `meetup_photos` so new photos
  appear live; the strip shows the first 6 with a `+N` overflow tile into the pager.

### M9.6 Truth or Dare game

Squad members in a meetup play Truth or Dare together with a synced virtual coin flip,
tiered prompt decks, photo-proof dares, and a pass scoreboard. Canonical migration:
`supabase/migrations/20260612100000_truth_or_dare.sql`.

Schema:

- `game_prompts (id, kind, tier, text)`: built-in prompt deck — `kind in ('truth','dare')`,
  `tier in ('normal','spicy')`, seeded with 60 prompts in the migration.
- `game_sessions (id, meetup_id, started_by, tier, status, turn_order, current_turn_index,
  created_at, ended_at)`: one session per game; `status in ('lobby','active','ended')`;
  a partial unique index allows only one live (lobby/active) session per meetup.
  `turn_order uuid[]` is randomized server-side when the game begins and loops via
  `current_turn_index`.
- `game_players (session_id, user_id, joined_at)`: who joined the session.
- `game_turns (id, session_id, turn_number, player_id, status, coin_result, prompt_kind,
  prompt_text, proof_photo_url, dare_locked, created_at, completed_at)`: one row per turn;
  `status: pending → prompted → completed | passed`. Dare proofs store the storage path
  in `proof_photo_url`. `dare_locked` gates custom dare assignment: false while another
  player is picking/editing the dare text, true once confirmed (truths are always
  immediately locked). Migration: `20260613000000_custom_dare_assignment.sql`.

Server-authoritative flow — clients are read-only on these tables; every mutation is a
SECURITY DEFINER RPC so the coin flip and prompt draw happen once, in Postgres, and sync
to all players via Realtime:

- `start_truth_or_dare(p_meetup_id, p_tier)`: participant creates a lobby and auto-joins.
- `join_truth_or_dare(p_session_id)`: participant joins the lobby; joining mid-game
  appends them to `turn_order`.
- `begin_truth_or_dare(p_session_id)`: starter only, needs ≥ 2 players; randomizes
  `turn_order` (`order by random()`) and creates the first turn.
- `flip_truth_or_dare_coin(p_turn_id)`: current player only; server picks heads/tails
  (`random() < 0.5` → heads = truth, tails = dare) and draws an unused prompt of the
  session's tier (falls back to reuse if the deck is exhausted). Sets `dare_locked = true`
  for truths immediately; dares start with `dare_locked = false` pending assignment.
- `assign_dare_prompt(p_turn_id, p_prompt_text)`: any game player who is NOT the current
  turn's player; confirms the app-suggested dare text or replaces it with a custom one,
  then sets `dare_locked = true`. First caller wins (race-safe). Doer is gated by
  `dare_locked` in the iOS UI.
- `complete_truth_or_dare_turn(p_turn_id, p_action, p_proof_path)`: current player only;
  `done` on a dare requires a proof path (the turn cannot advance without it), `pass`
  marks the chicken-out. Advances `current_turn_index` and inserts the next turn.
- `end_truth_or_dare(p_session_id)`: starter or meetup host; deletes the open turn and
  marks the session ended.

RLS:

- `game_prompts`: SELECT for any authenticated user.
- `game_sessions` / `game_players` / `game_turns`: SELECT for the meetup's host or
  participants (via `is_meetup_host` / `is_meetup_participant`). No INSERT/UPDATE/DELETE
  policies — writes only happen inside the RPCs.
- All three game tables are added to the `supabase_realtime` publication.

Storage:

- Dare proofs reuse the private `meetup-photos` bucket at `<meetup_id>/dares/<uuid>.jpg`,
  so the existing participant-scoped storage policies and 1-hour signed-URL flow apply.

iOS:

- `Models/TruthOrDare.swift`: `GameSession`, `GamePlayer`, `GameTurn`, `CoinFlipResult`,
  and `GameScoreboard.compute` (pure scoreboard tally, unit-tested in
  `GameScoreboardTests`).
- `TruthOrDareService`: reads + RPC wrappers + proof upload/signed-URL refresh.
- `TruthOrDareView` (full-screen cover from the dashboard's Game button): setup (tier
  pick), lobby, live game, and end-of-game scoreboard; keeps realtime subscriptions on
  the three game tables and reloads on any change.
- `CoinFlipView`: full-screen tap-to-flip coin (3D x-axis spin via a `GeometryEffect`,
  fast launch into a slow-motion settle, haptics on landing). The animation always lands
  on the server's result; observers watch the same flip when the turn syncs in. The
  prompt card appears only after the coin settles. Dare proof uses the in-app camera
  (`CameraPickerView`), with a photo-library fallback on camera-less devices.

### M9.7 Standalone Truth or Dare (Games tab)

Truth or Dare is decoupled from meetups: it is a first-class game mode on its own
"Games" tab, joinable with a short invite code. Meetup-embedded sessions still work,
but the meetup dashboard no longer exposes a Game button. Canonical migration:
`supabase/migrations/20260612200000_standalone_truth_or_dare.sql`.

Schema changes:

- `game_sessions.meetup_id` is now nullable — `NULL` means a standalone session.
  The partial unique "one live game per meetup" index is unaffected (NULLs are
  distinct), so any number of standalone games can run concurrently.
- `game_sessions.invite_code TEXT UNIQUE NOT NULL`: 6-char uppercase alphanumeric
  code (ambiguous 0/O/1/I excluded) generated server-side by
  `generate_game_invite_code()`; existing rows were backfilled.
- New helper `is_game_player(p_session_id, p_user_id)` (SECURITY DEFINER, STABLE):
  player-membership check usable inside the game tables' RLS policies without
  recursing into `game_players`' own policy.

RPC changes:

- `start_truth_or_dare(p_tier, p_meetup_id default null)` replaces the old
  `(p_meetup_id, p_tier)` signature. With no meetup, any authenticated user can
  start; with a meetup, membership and the one-live-game rule are enforced as
  before. Returns `(session_id, invite_code)`.
- `join_truth_or_dare_by_code(p_code)` (new): resolves the (case/whitespace
  normalized) code to a non-ended session, inserts the caller into `game_players`
  (appending to `turn_order` mid-game), and returns the session id.
- `join_truth_or_dare(p_session_id)`: meetup membership is only required when the
  session has a meetup; standalone sessions are joinable by session id (only
  discoverable via the invite code or a player's device).
- `end_truth_or_dare`: meetup-host override only applies when `meetup_id` is set;
  standalone games can only be ended by their starter.

RLS (SELECT on `game_sessions` / `game_players` / `game_turns`):

- `is_game_player(session, auth.uid())` — players always see their own games —
  OR (for meetup-embedded sessions) the previous meetup host/participant check.
  Writes still happen only inside the SECURITY DEFINER RPCs.

Storage:

- Standalone dare proofs go to the same private `meetup-photos` bucket under
  `games/<session_id>/dares/<uuid>.jpg` (the bucket's policies are
  authenticated-scoped, not path-scoped, so no storage policy change was needed).
  Meetup games keep `<meetup_id>/dares/<uuid>.jpg`.

iOS:

- `NavigationState.Tab` gains `.games`; `HomeView` adds a Games tab
  (`gamecontroller.fill`) between Messages and Settings.
- `GamesHomeView` (new): Start New Game (opens `TruthOrDareView()` at the tier
  pick), Join with Code (text field → `joinSessionByCode` → opens the game), and
  a recent-games list backed by `fetchMyGames()` (`game_players` rows for the
  current user with the session embedded).
- `TruthOrDareView` now has two inits: `init(sessionId: UUID? = nil)` for
  standalone games and `init(meetup: Meetup)` for the legacy embedded flow. The
  lobby shows the session's invite code in a copyable "Share code" chip.
- `TruthOrDareService`: `startSession(tier:)` / `startSession(meetupId:tier:)`
  both decode `StartGameResult (session_id, invite_code)`;
  `joinSessionByCode(code:)`, `fetchSessionByCode(code:)`, and `fetchMyGames()`
  are new; `uploadProofPhoto(image:sessionId:meetupId:)` picks the storage folder
  by mode.
- `MeetupDashboardView` no longer shows the Game action button (Directions and
  Split Bill remain).

### M9.8 Game Groups (Games tab)

Persistent named groups of friends for playing Truth or Dare together. The owner
creates a group, adds **accepted friends** as members, and starting a game from
the group stamps the session with the group id and pushes the invite code to
every other member. Canonical migration:
`supabase/migrations/20260612220000_game_groups.sql`.

Schema:

```sql
create table public.game_groups (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null check (char_length(trim(name)) between 1 and 60),
  owner_id   uuid        not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.game_group_members (
  group_id  uuid        not null references public.game_groups(id) on delete cascade,
  user_id   uuid        not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

alter table public.game_sessions
  add column group_id uuid references public.game_groups(id) on delete set null;
```

`owner_id` / `user_id` reference `public.profiles` (1:1 with `auth.users` here)
like the other game tables so PostgREST can embed `display_name` / `avatar_url`.
Deleting a group keeps its past sessions (`group_id` nulls out).

Helpers (SECURITY DEFINER, STABLE, so the group tables' RLS policies can use
them without recursing): `is_game_group_owner(group, user)` and
`is_game_group_member(group, user)`.

RLS (both tables have RLS enabled):

- `game_groups` SELECT: owner or member. INSERT: any authenticated user with
  `owner_id = auth.uid()`. UPDATE / DELETE: owner only.
- `game_group_members` SELECT: group owner or any member of the group (every
  member sees the full roster). INSERT: owner only (the friend gate lives in
  the RPC). DELETE: owner, or the member themselves (leave).

RPCs (all SECURITY DEFINER, authenticated-only):

- `create_game_group(p_name) → uuid`: creates the group and inserts the creator
  as the first member.
- `add_game_group_member(p_group_id, p_user_id)`: owner only; raises unless
  `is_accepted_friend(auth.uid(), p_user_id)` — only accepted friends of the
  owner can be added. Idempotent (`on conflict do nothing`).
- `remove_game_group_member(p_group_id, p_user_id)`: owner only; cannot remove
  the owner.
- `leave_game_group(p_group_id)`: any member; the owner cannot leave (delete
  the group instead).
- `start_truth_or_dare(p_tier, p_meetup_id default null, p_group_id default null)`:
  grew a third arg. A group game requires group membership, is mutually
  exclusive with `p_meetup_id`, stamps `game_sessions.group_id`, and fires
  `call_push_function('push-game-group-start', …)` (pg_net → edge function,
  wrapped so a push failure never fails the game start).

Push:

- `push-game-group-start` edge function (new): payload
  `{sessionId, groupId, starterId}`. Looks up the group name, the session's
  invite code, the starter's display name, and the other members'
  `profiles.apns_token`s, then sends
  **"🎮 [GroupName] — [Owner] started a game! Join with code [CODE]"**
  (`event: game_group_start`, includes `sessionId` for deep-linking) to each.
  Reuses the existing `_shared/apns.ts` sender + the vault-keyed
  `call_push_function` plumbing from M5.0.

iOS:

- Models: `GameGroup` (id, name, ownerId, createdAt, memberCount) and
  `GameGroupMember` (groupId, userId, joinedAt + embedded profile);
  `GameSession` gains optional `groupId`.
- `GameGroupService` (new): `fetchMyGroups()` (memberships with the group +
  member count embedded), `fetchMembers(groupId:)` (profile join),
  `createGroup(name:)`, `addMember`, `removeMember`, `leaveGroup` (RPCs),
  `deleteGroup` (direct delete, RLS-enforced), `fetchFriends()` (delegates to
  `MeetupService.getFriends()`).
- `TruthOrDareService.startSession(tier:groupId:)` passes the group to the RPC;
  `TruthOrDareView.init(sessionId:groupId:)` threads it from the UI.
- `GamesHomeView`: "My Groups" section (name + member count rows → push to
  `GameGroupView`) and a "New Group" button (name prompt → `createGroup`).
- `GameGroupView` (new): roster with crown badge on the owner; owner gets
  Add Member (friend picker sheet), per-row remove, and a destructive Delete
  Group; non-owners get Leave Group. Start Game opens `TruthOrDareView` in
  standalone mode stamped with the group — the lobby's copyable invite chip
  still covers late joiners.
- `AddGroupMemberView` (new): searchable list of the owner's accepted friends;
  already-members are grayed out; tapping adds immediately via `addMember`.

## Appendix C — Testing Strategy

- **Unit tests (backend):** `pytest`. Focus on `services/punctuality.py`, `services/routing.py` ETA caching logic.
- **Integration tests (backend):** Run a real Supabase test project. Use `pytest-asyncio` for async test cases.
- **iOS UI tests:** `XCTestCase` for `AuthViewModel`, `LocationManager` (use mock locations).
- **End-to-end:** Manual, with two devices, before each milestone closes.

## Appendix D — Common Pitfalls Quick Reference

| Symptom | Likely cause |
|---|---|
| Sign in with Apple fails immediately | Bundle ID mismatch between Xcode and Apple Developer |
| User's display_name is empty | Apple only sends name on first login; handle in trigger or capture immediately |
| Push notifications don't arrive | APNs sandbox vs production mismatch; check `use_sandbox` flag |
| Background location stops after 30s | Not actually using delegate callbacks; iOS kills inactive consumers |
| Realtime updates don't reach client | RLS policy blocks SELECT; verify with `select` policy |
| Tile flickers between colors | Hysteresis not applied; check `crossed_with_buffer` and `STATE_HOLD_SECONDS` |
| ETA wildly wrong | Mode inference says "stationary" when driving; `CMMotionActivityManager` lag |
| Webhook from Supabase fails | ngrok URL changed; re-update webhook config |
| RLS denies what should be allowed | Missing `using` vs `with check` distinction |
