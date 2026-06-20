import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

async function deleteCloudBackup(authHeader: string): Promise<void> {
  const workerURL = Deno.env.get("COLLECTION_SYNC_WORKER_URL")?.trim()
  if (!workerURL) return

  const base = workerURL.replace(/\/$/, "")
  const response = await fetch(`${base}/user-collection`, {
    method: "DELETE",
    headers: { Authorization: authHeader },
  })

  // Missing backup is fine; other failures should surface.
  if (response.status === 404) return
  if (!response.ok) {
    const body = await response.text()
    throw new Error(`Cloud backup deletion failed (${response.status}): ${body}`)
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405)
  }

  const authHeader = req.headers.get("Authorization")
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "Unauthorized" }, 401)
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? ""
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""

  if (!supabaseURL || !serviceRoleKey || !anonKey) {
    return json({ error: "Server configuration is incomplete" }, 500)
  }

  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser()

  if (userError || !user) {
    return json({ error: "Invalid session" }, 401)
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { error: rpcError } = await adminClient.rpc("delete_user_account", {
    p_user_id: user.id,
  })
  if (rpcError) {
    return json({ error: rpcError.message }, 500)
  }

  try {
    await deleteCloudBackup(authHeader)
  } catch (error) {
    const message = error instanceof Error ? error.message : "Cloud backup deletion failed"
    return json({ error: message }, 500)
  }

  const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(user.id)
  if (deleteUserError) {
    return json({ error: deleteUserError.message }, 500)
  }

  return json({ ok: true })
})
