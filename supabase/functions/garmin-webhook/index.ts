// ============================================================================
// Supabase Edge Function: garmin-webhook
// ============================================================================
// This receives webhooks from Garmin Health API and stores data in Supabase
//
// Deploy with:
// supabase functions deploy garmin-webhook
//
// Configure in Garmin Developer Portal:
// Push URL: https://YOUR_PROJECT.supabase.co/functions/v1/garmin-webhook
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  // Only accept POST requests
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Parse the webhook payload
    const payload = await req.json()
    
    console.log('📥 Received Garmin webhook:', JSON.stringify(payload).substring(0, 500))

    // Garmin sends data in format: { "dailies": [...], "sleeps": [...], etc }
    const results = []

    // Process dailies
    if (payload.dailies) {
      for (const daily of payload.dailies) {
        const result = await processDailySummary(supabase, daily)
        results.push(result)
      }
    }

    // Process sleeps
    if (payload.sleeps) {
      for (const sleep of payload.sleeps) {
        const result = await processSleepSummary(supabase, sleep)
        results.push(result)
      }
    }

    // Process stress details
    if (payload.stressDetails) {
      for (const stress of payload.stressDetails) {
        const result = await processStressDetails(supabase, stress)
        results.push(result)
      }
    }

    // Process body composition
    if (payload.bodyComps) {
      for (const bodyComp of payload.bodyComps) {
        const result = await processBodyComposition(supabase, bodyComp)
        results.push(result)
      }
    }

    console.log('✅ Processed webhook successfully')

    // IMPORTANT: Return 200 OK immediately (within 30 seconds)
    return new Response(
      JSON.stringify({ success: true, processed: results.length }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('❌ Webhook processing error:', error)
    
    // Still return 200 to prevent Garmin from retrying
    // Log the error for debugging
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      }
    )
  }
})

// ============================================================================
// Data Processing Functions
// ============================================================================

async function processDailySummary(supabase: any, daily: any) {
  const garminUserId = daily.userId
  
  // Get app user ID from mapping
  const { data: mapping } = await supabase
    .from('user_garmin_mapping')
    .select('user_id')
    .eq('garmin_user_id', garminUserId)
    .single()

  // FIX: Store data even if no mapping exists (use garmin_user_id as fallback)
  const appUserId = mapping?.user_id || garminUserId

  if (!mapping) {
    console.log(`⚠️ No app user mapping found for Garmin user ${garminUserId}, using Garmin ID as user_id`)
  }

  // Store in garmin_wellness table
  const { error } = await supabase
    .from('garmin_wellness')
    .upsert({
      user_id: appUserId,  // Use app user ID if available, otherwise Garmin ID
      garmin_user_id: garminUserId,
      data_type: 'dailies',
      calendar_date: daily.calendarDate,
      data: daily,
      synced_at: new Date().toISOString()
    }, {
      onConflict: 'user_id,garmin_user_id,data_type,calendar_date'
    })

  if (error) {
    console.error('❌ Failed to save daily:', error)
    return { type: 'daily', userId: garminUserId, status: 'error', error }
  }

  console.log(`✅ Saved daily for ${daily.calendarDate}`)
  return { type: 'daily', userId: garminUserId, date: daily.calendarDate, status: 'success' }
}

async function processSleepSummary(supabase: any, sleep: any) {
  const userId = sleep.userId
  
  const { data: mapping } = await supabase
    .from('user_garmin_mapping')
    .select('user_id')
    .eq('garmin_user_id', userId)
    .single()

  if (!mapping) {
    console.log(`⚠️ No app user found for Garmin user ${userId}`)
    return { type: 'sleep', userId, status: 'skipped' }
  }

  const { error } = await supabase
    .from('garmin_wellness')
    .upsert({
      user_id: mapping.user_id,
      garmin_user_id: userId,
      data_type: 'sleeps',
      calendar_date: sleep.calendarDate,
      data: sleep,
      synced_at: new Date().toISOString()
    }, {
      onConflict: 'user_id,garmin_user_id,data_type,calendar_date'
    })

  if (error) {
    console.error('❌ Failed to save sleep:', error)
    return { type: 'sleep', userId, status: 'error', error }
  }

  console.log(`✅ Saved sleep for ${sleep.calendarDate}`)
  return { type: 'sleep', userId, date: sleep.calendarDate, status: 'success' }
}

async function processStressDetails(supabase: any, stress: any) {
  const userId = stress.userId
  
  const { data: mapping } = await supabase
    .from('user_garmin_mapping')
    .select('user_id')
    .eq('garmin_user_id', userId)
    .single()

  if (!mapping) {
    return { type: 'stress', userId, status: 'skipped' }
  }

  const { error } = await supabase
    .from('garmin_wellness')
    .upsert({
      user_id: mapping.user_id,
      garmin_user_id: userId,
      data_type: 'stressDetails',
      calendar_date: stress.calendarDate,
      data: stress,
      synced_at: new Date().toISOString()
    }, {
      onConflict: 'user_id,garmin_user_id,data_type,calendar_date'
    })

  if (error) {
    console.error('❌ Failed to save stress:', error)
    return { type: 'stress', userId, status: 'error', error }
  }

  console.log(`✅ Saved stress for ${stress.calendarDate}`)
  return { type: 'stress', userId, date: stress.calendarDate, status: 'success' }
}

async function processBodyComposition(supabase: any, bodyComp: any) {
  const userId = bodyComp.userId
  
  const { data: mapping } = await supabase
    .from('user_garmin_mapping')
    .select('user_id')
    .eq('garmin_user_id', userId)
    .single()

  if (!mapping) {
    return { type: 'bodyComp', userId, status: 'skipped' }
  }

  // Convert timestamp to calendar date
  const date = new Date(bodyComp.measurementTimeInSeconds * 1000)
  const calendarDate = date.toISOString().split('T')[0]

  const { error } = await supabase
    .from('garmin_wellness')
    .upsert({
      user_id: mapping.user_id,
      garmin_user_id: userId,
      data_type: 'bodyComps',
      calendar_date: calendarDate,
      data: bodyComp,
      synced_at: new Date().toISOString()
    }, {
      onConflict: 'user_id,garmin_user_id,data_type,calendar_date'
    })

  if (error) {
    console.error('❌ Failed to save body composition:', error)
    return { type: 'bodyComp', userId, status: 'error', error }
  }

  console.log(`✅ Saved body composition for ${calendarDate}`)
  return { type: 'bodyComp', userId, date: calendarDate, status: 'success' }
}

// ============================================================================
// Setup Instructions:
// ============================================================================
/*

1. INSTALL SUPABASE CLI
   npm install -g supabase

2. LOGIN TO SUPABASE
   supabase login

3. LINK YOUR PROJECT
   supabase link --project-ref YOUR_PROJECT_REF

4. CREATE THIS FUNCTION
   supabase functions new garmin-webhook
   (Copy this code into: supabase/functions/garmin-webhook/index.ts)

5. DEPLOY THE FUNCTION
   supabase functions deploy garmin-webhook

6. GET YOUR FUNCTION URL
   It will be: https://YOUR_PROJECT.supabase.co/functions/v1/garmin-webhook

7. CONFIGURE GARMIN DEVELOPER PORTAL
   - Go to https://apis.garmin.com/tools/endpoints/
   - Log in with your Garmin developer credentials
   - Enable "dailies" and "sleeps" (and others you want)
   - Set Push URL to your Supabase function URL
   - Click Save

8. TEST IT
   - Sync your Garmin device
   - Check Supabase logs: supabase functions logs garmin-webhook
   - Check your garmin_wellness table for new data

9. UPDATE YOUR DATABASE SCHEMA (if needed)
   Make sure garmin_wellness table has a unique constraint:
   
   ALTER TABLE garmin_wellness ADD CONSTRAINT garmin_wellness_unique
   UNIQUE (user_id, garmin_user_id, data_type, calendar_date);

*/
