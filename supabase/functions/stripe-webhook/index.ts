// =============================================================================
// Webhook Stripe: после успешной оплаты обновляет `product_promotion_orders` и поля
// `promo_*_until` / `stats_access_until` в `products`. Вызывается только Stripe-серверами.
// Укажите STRIPE_WEBHOOK_SECRET из Stripe Dashboard → Webhooks.
// =============================================================================

import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";

serve(async (req) => {
  const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY");
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  if (!stripeSecret || !webhookSecret || !serviceKey || !supabaseUrl) {
    const missing = [
      !stripeSecret && "STRIPE_SECRET_KEY",
      !webhookSecret && "STRIPE_WEBHOOK_SECRET",
      !serviceKey && "SUPABASE_SERVICE_ROLE_KEY",
      !supabaseUrl && "SUPABASE_URL",
    ].filter(Boolean);
    return new Response(
      JSON.stringify({ error: "Missing secrets", missing }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const stripe = new Stripe(stripeSecret, {
    apiVersion: "2023-10-16",
    httpClient: Stripe.createFetchHttpClient(),
  });

  const signature = req.headers.get("stripe-signature");
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(body, signature!, webhookSecret);
  } catch {
    return new Response("Bad signature", { status: 400 });
  }

  if (event.type !== "checkout.session.completed") {
    return new Response("ignored", { status: 200 });
  }

  const session = event.data.object as Stripe.Checkout.Session;
  const orderId = session.metadata?.order_id ?? session.client_reference_id;
  if (!orderId) {
    return new Response("no order id", { status: 400 });
  }

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: order, error: oErr } = await admin
    .from("product_promotion_orders")
    .select("*")
    .eq("id", orderId)
    .single();

  if (oErr || !order) {
    return new Response("order not found", { status: 404 });
  }

  const durationHours = (order.duration_hours as number) ?? 24;
  const kind = order.kind as string;
  const productId = order.product_id as string;

  const until = new Date(Date.now() + durationHours * 3600 * 1000).toISOString();

  const patch: Record<string, string | boolean> = {};
  if (kind === "top") {
    patch.promo_top_until = until;
    patch.is_top = true;
  } else if (kind === "urgent") {
    patch.promo_urgent_until = until;
    patch.is_urgent = true;
  } else if (kind === "highlight") {
    patch.promo_highlight_until = until;
  } else if (kind === "stats") {
    patch.stats_access_until = until;
  }

  await admin.from("products").update(patch).eq("id", productId);

  await admin
    .from("product_promotion_orders")
    .update({
      status: "paid",
      paid_at: new Date().toISOString(),
      provider_ref: session.id,
    })
    .eq("id", orderId);

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
