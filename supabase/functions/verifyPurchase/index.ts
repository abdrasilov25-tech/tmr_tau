import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function normalizeSupabaseUrl(url: string): string {
  return url.trim().replace(/\/+$/, "");
}

/** Извлекает raw JWT из Bearer или возвращает строку как есть (без префикса). */
function extractJwtFromAuthHeader(authHeader: string): string {
  const t = authHeader.trim();
  const m = /^Bearer\s+(.+)$/i.exec(t);
  return (m?.[1] ?? t).trim();
}

function tryParseJsonObject(data: string): Record<string, unknown> | null {
  try {
    const j = JSON.parse(data) as unknown;
    if (j && typeof j === "object" && !Array.isArray(j)) {
      return j as Record<string, unknown>;
    }
  } catch {
    /* ignore */
  }
  return null;
}

function transactionIdFromPayload(obj: Record<string, unknown>): string | null {
  const keys = [
    "transactionId",
    "transaction_id",
    "originalTransactionId",
    "original_transaction_id",
  ];
  for (const k of keys) {
    const v = obj[k];
    if (v == null) continue;
    const s = String(v).trim();
    if (s) return s;
  }
  return null;
}

/** Расшифровка payload сегмента JWS (App Store signed transaction). */
function transactionIdFromJws(jws: string): string | null {
  const parts = jws.split(".");
  if (parts.length < 2) return null;
  try {
    let payload = parts[1];
    const pad = payload.length % 4;
    if (pad === 2) payload += "==";
    else if (pad === 3) payload += "=";
    const b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const json = atob(b64);
    const obj = tryParseJsonObject(json);
    return obj ? transactionIdFromPayload(obj) : null;
  } catch {
    return null;
  }
}

/**
 * Стабильный ключ одной IAP-транзакции: Apple purchaseId или transactionId из JWS/JSON,
 * иначе fp_<sha256-prefix> — чтобы redelivery при пустом purchaseId не плодил заказы.
 */
async function buildIapDedupeKey(
  purchaseId: string | null | undefined,
  verificationData: string,
): Promise<string> {
  const pid = (purchaseId ?? "").trim();
  if (pid) return pid;

  const trimmed = verificationData.trim();
  const fromJws = transactionIdFromJws(trimmed);
  if (fromJws) return fromJws;

  const asObj = tryParseJsonObject(trimmed);
  if (asObj) {
    const t = transactionIdFromPayload(asObj);
    if (t) return t;
  }

  const enc = new TextEncoder().encode(verificationData);
  const buf = await crypto.subtle.digest("SHA-256", enc);
  const hex = Array.from(new Uint8Array(buf))
    .slice(0, 16)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `fp_${hex}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const rawBody = await req.text();
    let body: Record<string, unknown> = {};
    if (rawBody?.trim()) {
      try {
        body = JSON.parse(rawBody) as Record<string, unknown>;
      } catch {
        return json(
          { error: "Invalid JSON body", error_code: "invalid_json" },
          400,
        );
      }
    }

    const rawAuth =
      req.headers.get("Authorization") ?? req.headers.get("authorization") ?? "";
    const tokenFromBody =
      typeof body.accessToken === "string" ? body.accessToken.trim() : "";

    let authHeader = rawAuth.trim();
    if (!authHeader && tokenFromBody) {
      authHeader = tokenFromBody.toLowerCase().startsWith("bearer ")
        ? tokenFromBody
        : `Bearer ${tokenFromBody}`;
    }
    if (authHeader && !authHeader.toLowerCase().startsWith("bearer ")) {
      authHeader = `Bearer ${authHeader}`;
    }

    const jwt = extractJwtFromAuthHeader(authHeader);
    if (!jwt) {
      return json(
        { error: "No Authorization", error_code: "no_authorization_header" },
        401,
      );
    }

    const supabaseUrl = normalizeSupabaseUrl(Deno.env.get("SUPABASE_URL") ?? "");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;

    if (!supabaseUrl) {
      return json(
        { error: "Server misconfiguration", error_code: "missing_supabase_url" },
        500,
      );
    }

    // Без глобального Authorization на клиенте: явный getUser(jwt) стабильнее в Edge.
    const userClient = createClient(supabaseUrl, anon);
    const { data: userData, error: userErr } = await userClient.auth.getUser(jwt);
    if (userErr || !userData.user) {
      const msg = userErr?.message ?? "no_user";
      return json(
        {
          error: "Unauthorized",
          error_code: "auth_get_user_failed",
          auth_message: msg,
        },
        401,
      );
    }
    const user = userData.user;

    const userId = String(body.userId ?? "");
    const productId = String(body.productId ?? "");
    const verificationData = String(body.verificationData ?? "");
    const source = String(body.source ?? "");
    const platform = String(body.platform ?? "");
    const purchaseId = body.purchaseId == null ? null : String(body.purchaseId);

    if (!userId || userId !== user.id) {
      return json(
        { error: "Forbidden", error_code: "user_id_mismatch" },
        403,
      );
    }
    if (!productId || !verificationData || !source || !platform) {
      return json({ error: "Invalid purchase payload" }, 400);
    }
    const officialPageProductIds = new Set([
      "com.bazar.tmrtau.subscription.monthly",
      "com.tmrtau.app.subscription.monthly",
      "com.example.tmrTau.subscription.monthly",
    ]);
    const cosmeticsForeverProductIds = new Set([
      "com.bazar.tmrtau.premium",
      "com.tmrtau.app.premium",
      "com.example.tmrTau.premium",
      "com.yourapp.premium",
    ]);
    const isSupportedProduct =
      productId === "boost_post" ||
      productId === "promote_post" ||
      productId === "premium_subscription" ||
      productId === "qarmet_10" ||
      productId === "qarmet_20" ||
      productId === "qarmet_30" ||
      productId === "qarmet_40" ||
      cosmeticsForeverProductIds.has(productId) ||
      officialPageProductIds.has(productId);
    if (!isSupportedProduct) {
      return json({ error: "Unsupported productId" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);
    const paymentKind =
      productId === "premium_subscription" ||
      officialPageProductIds.has(productId)
        ? "subscription"
        : cosmeticsForeverProductIds.has(productId)
          ? "cosmetics_forever"
          : "boost";

    const dedupeKey = await buildIapDedupeKey(purchaseId, verificationData);
    if (!dedupeKey.trim()) {
      return json({ error: "Invalid purchase payload (empty dedupe key)" }, 400);
    }

    const { data: existingRow } = await admin
      .from("payment_orders")
      .select("id")
      .eq("user_id", user.id)
      .eq("provider_payment_id", dedupeKey)
      .maybeSingle();
    let alreadyRecorded = existingRow != null;

    if (!alreadyRecorded) {
      const { error: insErr } = await admin.from("payment_orders").insert({
        user_id: user.id,
        provider: "iap",
        kind: paymentKind,
        plan_code: productId,
        amount_minor: 0,
        currency: "KZT",
        status: "paid",
        provider_payment_id: dedupeKey,
        provider_payload: {
          platform,
          source,
          client_purchase_id: purchaseId,
          verificationData,
        },
        paid_at: new Date().toISOString(),
      });
      if (insErr) {
        const code = (insErr as { code?: string }).code;
        if (code === "23505") {
          alreadyRecorded = true;
        } else {
          throw insErr;
        }
      }
    }

    if (cosmeticsForeverProductIds.has(productId)) {
      await admin
        .from("users")
        .update({
          profile_cosmetics_iap_forever: true,
          profile_premium_badge: true,
          profile_frame_level: 3,
          profile_badge_level: 3,
        })
        .eq("id", user.id);
    }

    if (officialPageProductIds.has(productId)) {
      const { data: currentUserRow } = await admin
        .from("users")
        .select("seller_plan")
        .eq("id", user.id)
        .maybeSingle();
      const currentPlan = String(currentUserRow?.seller_plan ?? "")
        .trim()
        .toLowerCase();
      const nextPlan = currentPlan === "pro" ? "pro" : "standard";
      await admin
        .from("users")
        .update({
          official_page_active: true,
          official_page_profile_perks: true,
          official_page_promo_perks: true,
          is_verified: true,
          seller_verified_store: true,
          seller_plan: nextPlan,
          official_page_last_credit_at: new Date().toISOString(),
        })
        .eq("id", user.id);
    }

    return json({ verified: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
