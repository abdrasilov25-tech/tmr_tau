/**
 * Agora RTC Token (Production-ready)
 *
 * Требует secrets:
 * AGORA_APP_ID
 * AGORA_APP_CERTIFICATE
 */

import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { RtcTokenBuilder, RtcRole } from "npm:agora-access-token@2.0.4";

// CORS
const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // =========================
    // AUTH
    // =========================
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "No Authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !anonKey) {
      return json(
        {
          error: "server_misconfigured",
          hint: "Missing SUPABASE_URL or SUPABASE_ANON_KEY",
        },
        500
      );
    }

    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } =
      await supabase.auth.getUser();

    if (userErr || !userData.user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const user = userData.user;

    // =========================
    // INPUT
    // =========================
    const body: Record<string, unknown> = await req
      .json()
      .catch(() => ({}));

    const channelName = String(
      body["channel_name"] ?? body["channelName"] ?? ""
    ).trim();

    const rawUid = Number(body["uid"]);
    const uid =
      Number.isFinite(rawUid) && rawUid > 0
        ? Math.floor(rawUid)
        : Math.floor(Math.random() * 100000);

    const role = String(body["role"] ?? "subscriber");

    if (!channelName || channelName.length > 64) {
      return json({ error: "Invalid channelName" }, 400);
    }

    // =========================
    // CHECK ROOM
    // =========================
    const { data: room, error: roomErr } = await supabase
      .from("live_rooms")
      .select("id, is_live, host_id")
      .eq("id", channelName)
      .maybeSingle();

    if (roomErr || !room) {
      return json({ error: "Room not found" }, 404);
    }

    if (!room.is_live) {
      return json({ error: "Room is not live" }, 400);
    }

    // только хост может стримить
    if (role === "publisher" && room.host_id !== user.id) {
      return json({ error: "Only host can publish" }, 403);
    }

    // =========================
    // AGORA SECRETS
    // =========================
    const appId = Deno.env.get("AGORA_APP_ID")?.trim();
    const appCertificate =
      Deno.env.get("AGORA_APP_CERTIFICATE")?.trim();

    if (!appId || !appCertificate) {
      return json(
        {
          error: "server_misconfigured",
          hint: "Добавь AGORA_APP_ID и AGORA_APP_CERTIFICATE",
        },
        500
      );
    }

    // =========================
    // TOKEN GENERATION
    // =========================
    const rtcRole =
      role === "publisher"
        ? RtcRole.PUBLISHER
        : RtcRole.SUBSCRIBER;

    const expire =
      Math.floor(Date.now() / 1000) + 3600 * 24; // 24 часа

    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      uid,
      rtcRole,
      expire
    );

    // =========================
    // RESPONSE
    // =========================
    return json({
      token,
      uid,
      channel: channelName,
      role,
      expires_at: expire,
    });

  } catch (err) {
    console.error(err);
    return json({ error: String(err) }, 500);
  }
});
