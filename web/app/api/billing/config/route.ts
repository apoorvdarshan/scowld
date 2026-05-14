import { NextResponse } from "next/server";
import { scowldMonetization } from "@/lib/monetization";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json(scowldMonetization, {
    headers: {
      "Cache-Control": "public, max-age=300, stale-while-revalidate=3600",
    },
  });
}
