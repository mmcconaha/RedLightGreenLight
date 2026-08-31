import { createClient } from "@supabase/supabase-js";

// SERVER-ONLY client using the service role key — bypasses row-level
// security. Never import this into any "use client" file or expose
// SUPABASE_SERVICE_ROLE_KEY as NEXT_PUBLIC_. Used only in trusted
// server-side routes like the Google Calendar sync callback, where we
// need to write availability rows on behalf of the authenticated user
// without a browser session to carry their auth.uid().
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);
