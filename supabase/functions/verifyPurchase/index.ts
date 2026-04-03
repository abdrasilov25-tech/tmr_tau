import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "No Authorization" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;

    const userClient = createClient(supabaseUrl, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return json({ error: "Unauthorized" }, 401);
    const user = userData.user;

    const body = await req.json();
    const userId = String(body.userId ?? "");
    const productId = String(body.productId ?? "");
    const verificationData = String(body.verificationData ?? "");
    const source = String(body.source ?? "");
    const platform = String(body.platform ?? "");
    const purchaseId = body.purchaseId == null ? null : String(body.purchaseId);

    if (!userId || userId !== user.id) return json({ error: "Forbidden" }, 403);
    if (!productId || !verificationData || !source || !platform) {
      return json({ error: "Invalid purchase payload" }, 400);
    }
    const officialPageProductIds = new Set([
      "com.bazar.tmrtau.subscription.monthly",
    ]);
    const cosmeticsForeverProductIds = new Set([
      "com.bazar.tmrtau.premium",
      "com.yourapp.premium", // legacy
    ]);
    const isSupportedProduct =
      productId === "boost_post" ||
      productId === "promote_post" || // Flutter PaymentService.promotePostProductId
      productId === "premium_subscription" ||
      productId === "qarmet_10" ||
      productId === "qarmet_20" ||
      productId === "qarmet_30" ||
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
          : "boost"; // boost_post, promote_post, qarmet_*

    // Idempotency: skip insert if this purchaseId was already recorded.
    // StoreKit can re-deliver the same transaction on next launch if completePurchase
    // was not called (e.g. network drop after insert but before completePurchase).
    let alreadyRecorded = false;
    if (purchaseId) {
      const { data: existing } = await admin
        .from("payment_orders")
        .select("id")
        .eq("provider_payment_id", purchaseId)
        .maybeSingle();
      alreadyRecorded = existing != null;
    }

    if (!alreadyRecorded) {
      await admin.from("payment_orders").insert({
        user_id: user.id,
        provider: "iap",
        kind: paymentKind,
        plan_code: productId,
        amount_minor: 0,
        currency: "KZT",
        status: "paid",
        provider_payment_id: purchaseId,
        provider_payload: {
          platform,
          source,
          verificationData,
        },
        paid_at: new Date().toISOString(),
      });
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
