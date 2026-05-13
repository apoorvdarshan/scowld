import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type ElevenLabsPayload = {
  voiceId?: string;
  body?: string | Record<string, unknown>;
  text?: string;
  model?: string;
};

const DEFAULT_VOICE_ID = "mHX7OoPk2G45VMAuinIt";
const DEFAULT_MODEL = "eleven_flash_v2_5";

export async function POST(request: NextRequest) {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "ELEVENLABS_API_KEY is not configured" }, { status: 500 });
  }

  let payload: ElevenLabsPayload;
  try {
    payload = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const voiceId = sanitizeVoiceId(payload.voiceId || process.env.ELEVENLABS_DEFAULT_VOICE_ID || DEFAULT_VOICE_ID);
  const model = payload.model || process.env.ELEVENLABS_MODEL || DEFAULT_MODEL;
  const providerBody = buildProviderBody(payload, model);

  if (!providerBody.text || typeof providerBody.text !== "string") {
    return NextResponse.json({ error: "Missing text for TTS" }, { status: 400 });
  }

  const upstream = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
    {
      method: "POST",
      headers: {
        Accept: "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": apiKey,
      },
      body: JSON.stringify(providerBody),
    },
  );

  if (!upstream.ok) {
    const detail = await upstream.text();
    return NextResponse.json(
      { error: "ElevenLabs request failed", detail: providerError(detail) },
      { status: upstream.status },
    );
  }

  const audio = await upstream.arrayBuffer();
  return new Response(audio, {
    status: 200,
    headers: {
      "Content-Type": upstream.headers.get("content-type") || "audio/mpeg",
      "Cache-Control": "no-store",
    },
  });
}

function buildProviderBody(payload: ElevenLabsPayload, model: string) {
  let body: Record<string, unknown> = {};

  if (typeof payload.body === "string") {
    try {
      body = JSON.parse(payload.body) as Record<string, unknown>;
    } catch {
      body = {};
    }
  } else if (payload.body && typeof payload.body === "object") {
    body = { ...payload.body };
  }

  if (payload.text) {
    body.text = payload.text;
  }

  body.model_id = model;
  if (!body.voice_settings) {
    body.voice_settings = {
      stability: 0.55,
      similarity_boost: 0.8,
      style: 0.35,
      use_speaker_boost: true,
    };
  }

  return body as { text?: unknown; model_id: string; voice_settings?: unknown };
}

function sanitizeVoiceId(voiceId: string) {
  return /^[A-Za-z0-9_-]+$/.test(voiceId) ? voiceId : DEFAULT_VOICE_ID;
}

function providerError(raw: string) {
  try {
    const json = JSON.parse(raw) as { detail?: { message?: string } | string; message?: string };
    if (typeof json.detail === "string") return json.detail;
    return json.detail?.message ?? json.message ?? raw;
  } catch {
    return raw;
  }
}
