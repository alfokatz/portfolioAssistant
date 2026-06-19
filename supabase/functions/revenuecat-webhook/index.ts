// RevenueCat webhook → updates user_subscriptions via service role.
// Deploy: supabase functions deploy revenuecat-webhook --no-verify-jwt
// Configure REVENUECAT_WEBHOOK_SECRET and map app_user_id → auth.users.id

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-revenuecat-signature",
};

type RevenueCatEvent = {
  event?: {
    type?: string;
    app_user_id?: string;
    product_id?: string;
    expiration_at_ms?: number | null;
  };
};

function tierFromProductId(productId: string | undefined): string {
  if (!productId) return "free";
  const id = productId.toLowerCase();
  if (id.includes("gold")) return "gold";
  if (id.includes("premium") || id.includes("pro")) return "premium";
  return "free";
}

function statusFromEventType(type: string | undefined): string {
  switch (type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "PRODUCT_CHANGE":
    case "UNCANCELLATION":
      return "active";
    case "CANCELLATION":
      return "canceled";
    case "EXPIRATION":
      return "expired";
    default:
      return "active";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
    if (secret) {
      const auth = req.headers.get("authorization");
      if (auth !== `Bearer ${secret}`) {
        return new Response(JSON.stringify({ error: "unauthorized" }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const payload = (await req.json()) as RevenueCatEvent;
    const event = payload.event;
    const userId = event?.app_user_id;
    if (!userId) {
      return new Response(JSON.stringify({ error: "missing app_user_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const eventType = event?.type;
    const tier =
      eventType === "EXPIRATION" ? "free" : tierFromProductId(event?.product_id);
    const status = statusFromEventType(eventType);
    const periodEnd = event?.expiration_at_ms
      ? new Date(event.expiration_at_ms).toISOString()
      : null;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { error } = await supabase.rpc("upsert_subscription_from_provider", {
      p_user_id: userId,
      p_tier: tier,
      p_provider: "revenuecat",
      p_external_subscription_id: event?.product_id ?? null,
      p_status: status,
      p_current_period_end: periodEnd,
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
