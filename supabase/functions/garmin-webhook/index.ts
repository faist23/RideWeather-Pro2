import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, garmin-client-id',
}

interface GarminSummary {
  userId: string
  callbackURL?: string
  summaryId?: string
  calendarDate?: string
  [key: string]: any
}

interface GarminPing {
  dailies?: GarminSummary[]
  sleeps?: GarminSummary[]
  stressDetails?: GarminSummary[]
  epochs?: GarminSummary[]
  bodyComps?: GarminSummary[]
  userMetrics?: GarminSummary[]
  pulseox?: GarminSummary[]
  allDayRespiration?: GarminSummary[]
  healthSnapshot?: GarminSummary[]
  hrv?: GarminSummary[]
  bloodPressures?: GarminSummary[]
  skinTemp?: GarminSummary[]
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const ping: GarminPing = await req.json()
    console.log('📍 Received Garmin ping:', JSON.stringify(ping, null, 2))

    let processedCount = 0
    let errorCount = 0

    // Process each summary type
    for (const [summaryType, summaries] of Object.entries(ping)) {
      if (!Array.isArray(summaries)) continue

      console.log(`\n🔄 Processing ${summaries.length} ${summaryType} notifications...`)

      for (const summary of summaries) {
        try {
          const { userId, callbackURL } = summary

          let data: any
          let calendarDate: string | null = null

          // MODE 1: Ping Service (has callbackURL)
          if (callbackURL) {
            console.log(`\n📥 Fetching ${summaryType} for user ${userId} from callback`)
            console.log(`   URL: ${callbackURL}`)

            const response = await fetch(callbackURL)
            
            if (!response.ok) {
              console.error(`❌ Failed to fetch ${summaryType}: ${response.status} ${response.statusText}`)
              errorCount++
              continue
            }

            data = await response.json()
            console.log(`✅ Fetched ${Array.isArray(data) ? data.length : 1} ${summaryType} record(s)`)

            // Extract calendar date from fetched data
            if (Array.isArray(data) && data.length > 0 && data[0].calendarDate) {
              calendarDate = data[0].calendarDate
            } else if (data.calendarDate) {
              calendarDate = data.calendarDate
            }
          }
          // MODE 2: Push Service (data is already in the summary)
          else {
            console.log(`\n📦 Processing ${summaryType} data directly from push notification`)
            
            // The summary itself IS the data
            data = summary
            calendarDate = summary.calendarDate || null
            
            console.log(`✅ Received ${summaryType} data for ${calendarDate || 'unknown date'}`)
          }

          // Store in database
          const recordToInsert = {
            garmin_user_id: userId,
            user_id: userId, // Will be mapped to actual user later via user_garmin_mapping
            data_type: summaryType,
            data: data,
            calendar_date: calendarDate,
            synced_at: new Date().toISOString()
          }

          console.log(`💾 Storing ${summaryType} data...`)

          const { error: insertError } = await supabase
            .from('garmin_wellness')
            .insert(recordToInsert)

          if (insertError) {
            console.error(`❌ Database insert error for ${summaryType}:`, insertError)
            errorCount++
          } else {
            console.log(`✅ Stored ${summaryType} data successfully`)
            processedCount++
          }

        } catch (error) {
          console.error(`❌ Error processing ${summaryType}:`, error)
          errorCount++
        }
      }
    }

    console.log(`\n✨ Processing complete: ${processedCount} succeeded, ${errorCount} failed`)

    return new Response(
      JSON.stringify({
        success: true,
        processed: processedCount,
        errors: errorCount
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    )

  } catch (error) {
    console.error('💥 Unhandled error:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500
      }
    )
  }
})
