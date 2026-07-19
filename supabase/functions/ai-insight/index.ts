// AI training-insight proxy.
//
// The iOS app sends the coaching prompt here instead of calling the
// Anthropic API directly, so the API key lives in Supabase secrets
// (ANTHROPIC_API_KEY) rather than shipping inside the app bundle.
// Model, token limits, and output schema are fixed server-side so the
// key can't be repurposed for arbitrary requests.

import Anthropic from 'npm:@anthropic-ai/sdk'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface InsightRequest {
  prompt: string
}

interface InsightResponse {
  priority: 'critical' | 'warning' | 'info'
  title: string
  insight: string
  explanation: string
  recommendation: string
  confidence: 'high' | 'moderate' | 'low'
}

// Matches AIInsightResponse in AIInsightsManager.swift
const insightSchema = {
  type: 'object',
  properties: {
    priority: { type: 'string', enum: ['critical', 'warning', 'info'] },
    title: { type: 'string', description: 'Brief title (max 50 chars)' },
    insight: { type: 'string', description: 'Main insight (2-3 sentences)' },
    explanation: { type: 'string', description: 'Why this matters (2-3 sentences)' },
    recommendation: { type: 'string', description: 'Specific action to take (1-2 sentences)' },
    confidence: { type: 'string', enum: ['high', 'moderate', 'low'] },
  },
  required: ['priority', 'title', 'insight', 'explanation', 'recommendation', 'confidence'],
  additionalProperties: false,
} as const

const MAX_PROMPT_LENGTH = 20_000

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY')
  if (!apiKey) {
    console.error('ANTHROPIC_API_KEY secret is not set')
    return jsonResponse({ error: 'Server misconfigured' }, 500)
  }

  let prompt: string
  try {
    const body = (await req.json()) as InsightRequest
    prompt = body.prompt
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400)
  }
  if (typeof prompt !== 'string' || prompt.length === 0 || prompt.length > MAX_PROMPT_LENGTH) {
    return jsonResponse({ error: 'prompt must be a non-empty string' }, 400)
  }

  const anthropic = new Anthropic({ apiKey })

  try {
    const message = await anthropic.messages.create({
      model: 'claude-sonnet-5',
      max_tokens: 1024,
      thinking: { type: 'disabled' },
      output_config: { format: { type: 'json_schema', schema: insightSchema } },
      messages: [{ role: 'user', content: prompt }],
    })

    if (message.stop_reason === 'refusal') {
      return jsonResponse({ error: 'Model declined the request' }, 502)
    }
    if (message.stop_reason === 'max_tokens') {
      return jsonResponse({ error: 'Response truncated' }, 502)
    }

    const textBlock = message.content.find((block) => block.type === 'text')
    if (!textBlock || textBlock.type !== 'text') {
      return jsonResponse({ error: 'No text content in model response' }, 502)
    }

    const insight = JSON.parse(textBlock.text) as InsightResponse

    return jsonResponse(
      {
        insight,
        usage: {
          input_tokens: message.usage.input_tokens,
          output_tokens: message.usage.output_tokens,
        },
      },
      200,
    )
  } catch (error) {
    if (error instanceof Anthropic.APIError) {
      console.error(`Anthropic API error ${error.status}: ${error.message}`)
      return jsonResponse({ error: `Anthropic API error: ${error.message}` }, 502)
    }
    console.error('Unexpected error:', error)
    return jsonResponse({ error: 'Internal error' }, 500)
  }
})
