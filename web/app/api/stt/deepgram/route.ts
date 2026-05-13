import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const DEFAULT_MODEL = "nova-3";

export async function POST(request: NextRequest) {
  const apiKey = process.env.DEEPGRAM_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "DEEPGRAM_API_KEY is not configured" }, { status: 500 });
  }

  const audio = await request.arrayBuffer();
  if (!audio.byteLength) {
    return NextResponse.json({ error: "Missing audio body" }, { status: 400 });
  }

  const model = request.nextUrl.searchParams.get("model") || process.env.DEEPGRAM_MODEL || DEFAULT_MODEL;
  const url = new URL("https://api.deepgram.com/v1/listen");
  url.searchParams.set("model", model);
  url.searchParams.set("smart_format", "true");

  const upstream = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Token ${apiKey}`,
      "Content-Type": request.headers.get("content-type") || "audio/wav",
    },
    body: audio,
  });

  const raw = await upstream.text();
  if (!upstream.ok) {
    return NextResponse.json(
      { error: "Deepgram request failed", detail: providerError(raw) },
      { status: upstream.status },
    );
  }

  try {
    const json = JSON.parse(raw);
    return NextResponse.json({ text: extractTranscript(json), model });
  } catch {
    return NextResponse.json({ error: "Invalid Deepgram response" }, { status: 502 });
  }
}

function extractTranscript(json: unknown) {
  const response = json as {
    results?: { channels?: Array<{ alternatives?: Array<{ transcript?: string }> }> };
  };
  return response.results?.channels?.[0]?.alternatives?.[0]?.transcript?.trim() ?? "";
}

function providerError(raw: string) {
  try {
    const json = JSON.parse(raw) as { error?: string; message?: string };
    return json.message ?? json.error ?? raw;
  } catch {
    return raw;
  }
}
