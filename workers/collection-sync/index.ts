/**
 * Cloudflare Worker — Collection Sync
 *
 * Stores and retrieves per-user collection snapshots in a private R2 bucket.
 * All requests require a valid Supabase JWT (Bearer token). Read access to
 * another user's snapshot requires a confirmed friendship in Supabase.
 *
 * Routes:
 *   PUT /user-collection          — upload the caller's snapshot
 *   GET /user-collection?userID=  — download a snapshot (self or friend)
 *   DELETE /user-collection       — delete the caller's snapshot
 */

export interface Env {
  COLLECTION_BUCKET: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return corsResponse(new Response(null, { status: 204 }));
    }

    const token = bearerToken(request);
    if (!token) return corsResponse(json({ error: "Unauthorized" }, 401));

    const callerID = await verifyJWT(token, env);
    if (!callerID) return corsResponse(json({ error: "Invalid token" }, 401));

    if (request.method === "PUT" && url.pathname === "/user-collection") {
      return corsResponse(await handlePut(request, env, callerID));
    }

    if (request.method === "GET" && url.pathname === "/user-collection") {
      const targetUserID = url.searchParams.get("userID");
      if (!targetUserID) return corsResponse(json({ error: "Missing userID" }, 400));
      return corsResponse(await handleGet(env, callerID, targetUserID));
    }

    if (request.method === "DELETE" && url.pathname === "/user-collection") {
      return corsResponse(await handleDelete(env, callerID));
    }

    return corsResponse(json({ error: "Not found" }, 404));
  },
};

// ---------------------------------------------------------------------------
// PUT — upload caller's snapshot
// ---------------------------------------------------------------------------

async function handlePut(request: Request, env: Env, callerID: string): Promise<Response> {
  const body = await request.text();
  if (!body) return json({ error: "Empty body" }, 400);

  // Sanity-check the payload is valid JSON
  try {
    JSON.parse(body);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const key = snapshotKey(callerID);

  // Never overwrite a non-empty backup with an empty library — protects against
  // fresh installs uploading before iCloud restore completes.
  try {
    const parsed = JSON.parse(body) as {
      collection?: unknown[];
      wishlist?: unknown[];
      library?: Record<string, unknown[] | undefined>;
    };
    if (!snapshotHasData(parsed)) {
      const existing = await env.COLLECTION_BUCKET.get(key);
      if (existing) {
        const existingBody = await existing.text();
        const existingParsed = JSON.parse(existingBody) as {
          collection?: unknown[];
          wishlist?: unknown[];
          library?: Record<string, unknown[] | undefined>;
        };
        if (snapshotHasData(existingParsed)) {
          return json({ error: "Refusing to overwrite non-empty backup with empty snapshot" }, 409);
        }
      }
    }
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  await env.COLLECTION_BUCKET.put(key, body, {
    httpMetadata: { contentType: "application/json" },
    customMetadata: { updatedAt: new Date().toISOString() },
  });

  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// DELETE — remove the caller's snapshot
// ---------------------------------------------------------------------------

async function handleDelete(env: Env, callerID: string): Promise<Response> {
  const key = snapshotKey(callerID);
  await env.COLLECTION_BUCKET.delete(key);
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// GET — download a snapshot
// ---------------------------------------------------------------------------

async function handleGet(env: Env, callerID: string, targetUserID: string): Promise<Response> {
  console.log("[handleGet] callerID:", callerID, "targetUserID:", targetUserID, "same:", callerID === targetUserID);
  // Self-access is always allowed
  if (callerID !== targetUserID) {
    const isFriend = await checkFriendship(env, callerID, targetUserID);
    console.log("[handleGet] isFriend:", isFriend);
    if (!isFriend) return json({ error: "Forbidden" }, 403);
  }

  const key = snapshotKey(targetUserID);
  const object = await env.COLLECTION_BUCKET.get(key);
  if (!object) return json({ error: "Not found" }, 404);

  const body = await object.text();
  return new Response(body, {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function snapshotKey(userID: string): string {
  return `user-collections/${userID.toLowerCase()}/collection.json`;
}

function snapshotHasData(parsed: {
  collection?: unknown[];
  wishlist?: unknown[];
  library?: Record<string, unknown[] | undefined>;
}): boolean {
  if ((parsed.collection?.length ?? 0) > 0) return true;
  if ((parsed.wishlist?.length ?? 0) > 0) return true;
  const library = parsed.library;
  if (!library) return false;
  return Object.values(library).some((value) => Array.isArray(value) && value.length > 0);
}

function bearerToken(request: Request): string | null {
  const auth = request.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  return auth.slice(7).trim() || null;
}

/**
 * Verifies a Supabase JWT by calling the Supabase Auth endpoint.
 * Returns the user's UUID string on success, null on failure.
 */
async function verifyJWT(token: string, env: Env): Promise<string | null> {
  try {
    const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
      headers: {
        Authorization: `Bearer ${token}`,
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      },
    });
    if (!response.ok) return null;
    const user = await response.json() as { id?: string };
    return user.id ?? null;
  } catch {
    return null;
  }
}

/**
 * Checks whether callerID and targetUserID have an accepted friendship row
 * in Supabase.
 */
async function checkFriendship(env: Env, callerID: string, targetUserID: string): Promise<boolean> {
  try {
    const orFilter = `or(and(requester_id.eq.${callerID},addressee_id.eq.${targetUserID}),and(requester_id.eq.${targetUserID},addressee_id.eq.${callerID}))`;
    const url = `${env.SUPABASE_URL}/rest/v1/friendships?select=id&status=eq.accepted&${orFilter}&limit=1`;
    console.log("[checkFriendship] callerID:", callerID, "targetUserID:", targetUserID);
    console.log("[checkFriendship] url:", url);
    const response = await fetch(url, {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    });
    console.log("[checkFriendship] status:", response.status);
    const body = await response.text();
    console.log("[checkFriendship] body:", body);
    if (!response.ok) return false;
    const rows = JSON.parse(body) as unknown[];
    return rows.length > 0;
  } catch (e) {
    console.log("[checkFriendship] error:", e);
    return false;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function corsResponse(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Access-Control-Allow-Methods", "GET, PUT, DELETE, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  return new Response(response.body, { status: response.status, headers });
}
