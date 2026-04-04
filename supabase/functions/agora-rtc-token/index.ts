/**
 * RTC-токен для Agora (когда в консоли Agora включён App Certificate).
 *
 * Секреты (Supabase → Edge Functions → Secrets):
 *   AGORA_APP_ID
 *   AGORA_APP_CERTIFICATE
 *
 * Деплой: supabase functions deploy agora-rtc-token
 *
 * Тело POST JSON:
 *   { "channel_name": "<uuid комнаты live_rooms>", "uid": <int>, "role": "publisher" | "subscriber" }
 */
import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { RtcTokenBuilder, RtcRole } from "npm:agora-access-token@2.0.4";

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
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "No Authorization" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const userClient = createClient(supabaseUrl, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return json({ error: "Unauthorized" }, 401);
    const user = userData.user;

    const body = await req.json().catch(() => ({}));
    const channelName = String(body.channel_name ?? "").trim();
    const uid = Number(body.uid);
    const role = String(body.role ?? "subscriber");

    if (!channelName || channelName.length > 64) {
      return json({ error: "Invalid channel_name" }, 400);
    }
    if (!Number.isInteger(uid) || uid < 1) {
      return json({ error: "Invalid uid" }, 400);
    }

    const { data: room, error: roomErr } = await userClient
      .from("live_rooms")
      .select("id, is_live, host_id")
      .eq("id", channelName)
      .maybeSingle();

    if (roomErr || !room) {
      return json({ error: "Room not found" }, 404);
    }
    if (!room.is_live) {
      return json({ error: "Room not live" }, 404);
    }
    if (role === "publisher" && room.host_id !== user.id) {
      return json({ error: "Only host can publish" }, 403);
    }

    const appId = Deno.env.get("AGORA_APP_ID")?.trim();
    const cert = Deno.env.get("AGORA_APP_CERTIFICATE")?.trim();
    if (!appId || !cert) {
      return json(
        {
          error: "server_misconfigured",
          hint:
            "Добавьте секреты AGORA_APP_ID и AGORA_APP_CERTIFICATE для этой функции, либо в Agora Console отключите App Certificate и оставьте токен пустым в клиенте.",
        },
        503,
      );
    }

    const rtcRole = role === "publisher"
      ? RtcRole.PUBLISHER
      : RtcRole.SUBSCRIBER;
    const expire = Math.floor(Date.now() / 1000) + 24 * 3600;
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      cert,
      channelName,
      uid,
      rtcRole,
      expire,
    );

    return json({ token, expires_at: expire });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});
