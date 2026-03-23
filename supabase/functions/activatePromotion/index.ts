import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const amountByKind: Record<string, number> = {
  top: 490_00,
  urgent: 390_00,
  highlight: 590_00,
  stats: 290_00,
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "No Authorization" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY");

    if (!stripeSecret) {
      return json(
        {
          error:
            "STRIPE_SECRET_KEY is not set. Add it in Edge Function secrets.",
        },
        500,
      );
    }

    const userClient = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return json({ error: "Unauthorized" }, 401);
    const user = userData.user;

    const body = await req.json();
    const userId = body.userId as string;
    const productId = body.productId as string;
    const promoType = body.promoType as string;

    if (!productId || !promoType || !(promoType in amountByKind)) {
      return json({ error: "Invalid productId or promoType" }, 400);
    }
    if (!userId || userId !== user.id) {
      return json({ error: "Forbidden" }, 403);
    }

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: product, error: pErr } = await admin
      .from("products")
      .select("id, seller_id")
      .eq("id", productId)
      .single();

    if (pErr || !product) return json({ error: "Product not found" }, 404);
    if (product.seller_id !== user.id) return json({ error: "Forbidden" }, 403);

    const amount = amountByKind[promoType]!;
    const durationHours = 24;

    const { data: order, error: oErr } = await admin
      .from("product_promotion_orders")
      .insert({
        product_id: productId,
        seller_id: user.id,
        kind: promoType,
        status: "pending",
        provider: "stripe",
        amount_minor: amount,
        currency: "KZT",
        duration_hours: durationHours,
      })
      .select()
      .single();

    if (oErr || !order) {
      return json({ error: oErr?.message ?? "Order insert failed" }, 500);
    }

    const stripe = new Stripe(stripeSecret, {
      apiVersion: "2023-10-16",
      httpClient: Stripe.createFetchHttpClient(),
    });

    const rawBase = Deno.env.get("PUBLIC_APP_URL") ?? "https://example.com";
    const publicAppUrl = rawBase.replace(/\/+$/, "");

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      success_url: `${publicAppUrl}/?payment=ok&order_id=${order.id}`,
      cancel_url: `${publicAppUrl}/?payment=cancel`,
      client_reference_id: order.id as string,
      metadata: {
        order_id: order.id as string,
        product_id: productId,
        kind: promoType,
      },
      line_items: [
        {
          price_data: {
            currency: "kzt",
            unit_amount: amount,
            product_data: {
              name: `Temirtau — продвижение (${promoType})`,
            },
          },
          quantity: 1,
        },
      ],
    });

    await admin
      .from("product_promotion_orders")
      .update({ provider_ref: session.id })
      .eq("id", order.id);

    return json({
      checkout_url: session.url,
      order_id: order.id,
      provider: "stripe",
      amount_minor: amount,
      currency: "KZT",
    });
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
