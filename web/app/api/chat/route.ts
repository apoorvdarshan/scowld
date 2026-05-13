import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type ChatMessage = {
  role?: string;
  content?: string;
};

type ChatRequest = {
  model?: string;
  messages?: ChatMessage[];
  systemPrompt?: string;
  imageBase64?: string | null;
};

const DEFAULT_GEMINI_FALLBACKS = [
  "gemini-3.1-pro-preview",
  "gemini-3-flash-preview",
  "gemini-3.1-flash-lite",
  "gemini-2.5-pro",
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
];

export async function POST(request: NextRequest) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "GEMINI_API_KEY is not configured" }, { status: 500 });
  }

  let payload: ChatRequest;
  try {
    payload = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const messages = Array.isArray(payload.messages) ? payload.messages : [];
  const contents = buildGeminiContents(messages, payload.imageBase64 ?? undefined);
  const systemPrompt = typeof payload.systemPrompt === "string" ? payload.systemPrompt : "";
  const fallbackModels = modelFallbacks(payload.model);

  let lastError = "No Gemini model was attempted.";

  for (const model of fallbackModels) {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents,
          systemInstruction: { parts: [{ text: systemPrompt }] },
          generationConfig: {
            temperature: 0.8,
            maxOutputTokens: 1024,
          },
        }),
      },
    );

    const raw = await response.text();
    if (!response.ok) {
      lastError = providerError(raw) || `Gemini ${model} returned HTTP ${response.status}`;
      continue;
    }

    try {
      const json = JSON.parse(raw);
      const text = extractGeminiText(json);
      if (text) {
        return NextResponse.json({
          text,
          model,
          fallbackUsed: model !== fallbackModels[0],
        });
      }
      lastError = `Gemini ${model} returned an empty response.`;
    } catch {
      lastError = `Gemini ${model} returned invalid JSON.`;
    }
  }

  return NextResponse.json({ error: "Gemini request failed", detail: lastError }, { status: 502 });
}

function modelFallbacks(requestedModel?: string) {
  const envModels = process.env.GEMINI_MODEL_FALLBACKS?.split(",")
    .map((model) => model.trim())
    .filter(Boolean);
  const models = envModels?.length ? envModels : DEFAULT_GEMINI_FALLBACKS;
  const requested = requestedModel?.trim();

  if (requested && !models.includes(requested)) {
    return [requested, ...models];
  }
  return models;
}

function buildGeminiContents(messages: ChatMessage[], imageBase64?: string) {
  const cleaned = messages
    .filter((message) => message.role !== "system")
    .map((message) => ({
      role: message.role === "assistant" ? "model" : "user",
      content: String(message.content ?? ""),
    }))
    .filter((message) => message.content.trim().length > 0);

  const source = cleaned.length ? cleaned : [{ role: "user", content: "Hello" }];
  const lastUserIndex = findLastUserIndex(source);

  return source.map((message, index) => {
    const parts: Array<Record<string, unknown>> = [{ text: message.content }];
    if (imageBase64 && index === lastUserIndex) {
      parts.push({ inline_data: { mime_type: "image/jpeg", data: imageBase64 } });
    }
    return { role: message.role, parts };
  });
}

function findLastUserIndex(messages: Array<{ role: string }>) {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    if (messages[index].role === "user") {
      return index;
    }
  }
  return messages.length - 1;
}

function extractGeminiText(json: unknown) {
  const candidate = (json as { candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }> })
    .candidates?.[0];
  return candidate?.content?.parts
    ?.map((part) => part.text ?? "")
    .join("")
    .trim();
}

function providerError(raw: string) {
  try {
    const json = JSON.parse(raw) as { error?: { message?: string }; message?: string };
    return json.error?.message ?? json.message ?? raw;
  } catch {
    return raw;
  }
}
