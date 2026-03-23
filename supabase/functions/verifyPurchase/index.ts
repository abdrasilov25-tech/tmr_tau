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
    if (productId !== "boost_post" && productId !== "premium_subscription") {
      return json({ error: "Unsupported productId" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);
    await admin.from("payment_orders").insert({
      user_id: user.id,
      provider: "iap",
      kind: productId === "premium_subscription" ? "subscription" : "boost",
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
