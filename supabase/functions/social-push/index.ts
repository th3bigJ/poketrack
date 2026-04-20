import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6"

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE"
  table: string
  schema: string
  record: Record<string, unknown> | null
  old_record: Record<string, unknown> | null
}

type PushCandidate = {
  userID: string
  category:
    | "friend_requests"
    | "friend_accepts"
    | "shared_content_posts"
    | "comments"
    | "wishlist_matches"
  title: string
  body: string
  deepLink: string
  metadata: Record<string, unknown>
}

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
)

const APNS_TOPIC = Deno.env.get("APNS_TOPIC") ?? ""
const APNS_ENV = Deno.env.get("APNS_ENV") ?? "sandbox"
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? ""
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? ""
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? ""

const APNS_HOST =
  APNS_ENV.toLowerCase() === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com"

function asString(value: unknown): string | null {
  if (typeof value !== "string") return null
  return value
}

function isUUID(value: string | null): value is string {
  if (!value) return false
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

async function pushEnabledForUser(userID: string, category: PushCandidate["category"]) {
  const { data, error } = await supabase
    .from("notification_preferences")
    .select(category)
    .eq("user_id", userID)
    .single()

  if (error || !data) return false
  return Boolean((data as Record<string, unknown>)[category])
}

async function fetchDeviceTokens(userID: string): Promise<string[]> {
  const { data, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", userID)

  if (error || !data) return []
  return data
    .map((row) => asString((row as Record<string, unknown>).token))
    .filter((token): token is string => Boolean(token))
}

async function apnsBearerToken(): Promise<string | null> {
  if (!APNS_TEAM_ID || !APNS_KEY_ID || !APNS_PRIVATE_KEY) return null
  try {
    const privateKey = APNS_PRIVATE_KEY.replace(/\\n/g, "\n")
    const key = await importPKCS8(privateKey, "ES256")
    return await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: APNS_KEY_ID })
      .setIssuer(APNS_TEAM_ID)
      .setIssuedAt()
      .sign(key)
  } catch {
    return null
  }
}

async function writeLog(
  candidate: PushCandidate,
  deviceToken: string | null,
  status: "sent" | "skipped" | "failed",
  errorMessage: string | null
) {
  await supabase.from("push_delivery_log").insert({
    event_type: candidate.category,
    target_user_id: candidate.userID,
    device_token: deviceToken,
    payload: {
      title: candidate.title,
      body: candidate.body,
      deep_link: candidate.deepLink,
      metadata: candidate.metadata,
    },
    status,
    error_message: errorMessage,
  })
}

async function sendApnsPush(candidate: PushCandidate) {
  const enabled = await pushEnabledForUser(candidate.userID, candidate.category)
  if (!enabled) {
    await writeLog(candidate, null, "skipped", "notification preference disabled")
    return
  }

  const tokens = await fetchDeviceTokens(candidate.userID)
  if (tokens.length === 0) {
    await writeLog(candidate, null, "skipped", "no device tokens found")
    return
  }

  const bearer = await apnsBearerToken()
  if (!bearer || !APNS_TOPIC) {
    for (const token of tokens) {
      await writeLog(candidate, token, "skipped", "missing APNs secrets or topic")
    }
    return
  }

  for (const token of tokens) {
    try {
      const payload = {
        aps: {
          alert: {
            title: candidate.title,
            body: candidate.body,
          },
          sound: "default",
          badge: 1,
        },
        deep_link: candidate.deepLink,
        category: candidate.category,
        metadata: candidate.metadata,
      }
      const response = await fetch(`https://${APNS_HOST}/3/device/${token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${bearer}`,
          "apns-topic": APNS_TOPIC,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      })

      if (!response.ok) {
        const raw = await response.text()
        await writeLog(candidate, token, "failed", `apns ${response.status}: ${raw}`)
        continue
      }
      await writeLog(candidate, token, "sent", null)
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown APNs error"
      await writeLog(candidate, token, "failed", message)
    }
  }
}

function buildCandidate(payload: WebhookPayload): PushCandidate | null {
  const record = payload.record ?? {}
  const oldRecord = payload.old_record ?? {}

  switch (payload.table) {
    case "friendships": {
      const requesterID = asString(record.requester_id)
      const addresseeID = asString(record.addressee_id)
      const status = asString(record.status)
      const oldStatus = asString(oldRecord.status)
      if (!isUUID(requesterID) || !isUUID(addresseeID)) return null

      if (payload.type === "INSERT" && status === "pending") {
        return {
          userID: addresseeID,
          category: "friend_requests",
          title: "New friend request",
          body: "Someone sent you a friend request.",
          deepLink: "bindr://social/friends/requests",
          metadata: { requester_id: requesterID, addressee_id: addresseeID },
        }
      }

      if (payload.type === "UPDATE" && oldStatus !== "accepted" && status === "accepted") {
        return {
          userID: requesterID,
          category: "friend_accepts",
          title: "Friend request accepted",
          body: "Your friend request was accepted.",
          deepLink: "bindr://social/friends",
          metadata: { requester_id: requesterID, addressee_id: addresseeID },
        }
      }
      return null
    }

    case "shared_content": {
      if (payload.type !== "INSERT") return null
      const ownerID = asString(record.owner_id)
      const contentID = asString(record.id)
      const title = asString(record.title) ?? "New shared content"
      if (!isUUID(ownerID) || !isUUID(contentID)) return null
      // Use placeholder recipient marker. Handler will fan-out in database via query.
      return {
        userID: ownerID,
        category: "shared_content_posts",
        title: "New shared content",
        body: title,
        deepLink: `bindr://social/feed/content/${contentID}`,
        metadata: { owner_id: ownerID, content_id: contentID },
      }
    }

    case "comments": {
      if (payload.type !== "INSERT") return null
      const contentID = asString(record.content_id)
      const authorID = asString(record.author_id)
      const commentID = asString(record.id)
      if (!isUUID(contentID) || !isUUID(authorID) || !isUUID(commentID)) return null
      return {
        userID: authorID,
        category: "comments",
        title: "New comment",
        body: "Someone commented on your shared content.",
        deepLink: `bindr://social/feed/comment/${commentID}`,
        metadata: { content_id: contentID, author_id: authorID, comment_id: commentID },
      }
    }

    case "wishlist_matches": {
      if (payload.type !== "INSERT") return null
      const contentID = asString(record.content_id)
      const senderID = asString(record.sender_id)
      const matchID = asString(record.id)
      if (!isUUID(contentID) || !isUUID(senderID) || !isUUID(matchID)) return null
      return {
        userID: senderID,
        category: "wishlist_matches",
        title: "Wishlist match",
        body: "A friend has a card from your wishlist.",
        deepLink: `bindr://social/feed/wishlist-match/${matchID}`,
        metadata: { content_id: contentID, sender_id: senderID, match_id: matchID },
      }
    }

    default:
      return null
  }
}

async function expandRecipients(candidate: PushCandidate): Promise<PushCandidate[]> {
  if (candidate.category === "shared_content_posts") {
    const ownerID = candidate.userID
    const { data, error } = await supabase
      .from("friendships")
      .select("requester_id,addressee_id,status")
      .eq("status", "accepted")
      .or(`requester_id.eq.${ownerID},addressee_id.eq.${ownerID}`)

    if (error || !data) return []

    const recipients = data
      .map((row) => {
        const requester = asString((row as Record<string, unknown>).requester_id)
        const addressee = asString((row as Record<string, unknown>).addressee_id)
        if (!isUUID(requester) || !isUUID(addressee)) return null
        return requester === ownerID ? addressee : requester
      })
      .filter((value): value is string => Boolean(value))
    const uniqueRecipients = [...new Set(recipients)]
    return uniqueRecipients.map((userID) => ({ ...candidate, userID }))
  }

  if (candidate.category === "comments") {
    const contentID = asString(candidate.metadata.content_id)
    const authorID = asString(candidate.metadata.author_id)
    if (!isUUID(contentID) || !isUUID(authorID)) return []
    const { data, error } = await supabase
      .from("shared_content")
      .select("owner_id")
      .eq("id", contentID)
      .single()
    if (error || !data) return []
    const ownerID = asString((data as Record<string, unknown>).owner_id)
    if (!isUUID(ownerID) || ownerID === authorID) return []
    return [{ ...candidate, userID: ownerID }]
  }

  if (candidate.category === "wishlist_matches") {
    const contentID = asString(candidate.metadata.content_id)
    const senderID = asString(candidate.metadata.sender_id)
    if (!isUUID(contentID) || !isUUID(senderID)) return []
    const { data, error } = await supabase
      .from("shared_content")
      .select("owner_id")
      .eq("id", contentID)
      .single()
    if (error || !data) return []
    const ownerID = asString((data as Record<string, unknown>).owner_id)
    if (!isUUID(ownerID) || ownerID === senderID) return []
    return [{ ...candidate, userID: ownerID }]
  }

  return [candidate]
}

Deno.serve(async (req) => {
  try {
    const payload = (await req.json()) as WebhookPayload
    const candidate = buildCandidate(payload)
    if (!candidate) {
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { "content-type": "application/json" },
      })
    }

    const recipients = await expandRecipients(candidate)
    for (const recipient of recipients) {
      await sendApnsPush(recipient)
    }

    return new Response(
      JSON.stringify({
        ok: true,
        event: payload.table,
        deliveredCandidates: recipients.length,
      }),
      { headers: { "content-type": "application/json" } }
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown error"
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 500,
      headers: { "content-type": "application/json" },
    })
  }
})
