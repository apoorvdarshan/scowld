import { NextResponse } from "next/server";
import { scowldMonetization } from "@/lib/monetization";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const revenueCat = {
    iosApiKey: process.env.REVENUECAT_IOS_API_KEY || null,
    entitlementID: process.env.REVENUECAT_ENTITLEMENT_ID || "Scowld Plus",
    offeringID: process.env.REVENUECAT_OFFERING_ID || "default",
    appStoreAppID: process.env.APP_STORE_APP_ID || "6760672848",
    isConfigured: Boolean(process.env.REVENUECAT_IOS_API_KEY),
  };

  return NextResponse.json({ ...scowldMonetization, revenueCat }, {
    headers: {
      "Cache-Control": "no-store",
    },
  });
}
