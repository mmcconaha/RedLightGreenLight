// One-time local script — resets a user's password directly using the
// service role key. Run once, then delete this file.
const { createClient } = require("@supabase/supabase-js");

// Paste these from your .env.local file:
const SUPABASE_URL = "PASTE_NEXT_PUBLIC_SUPABASE_URL_HERE";
const SERVICE_ROLE_KEY = "PASTE_SUPABASE_SERVICE_ROLE_KEY_HERE";

const EMAIL = "m.mcconaha@feverdreamevents.com";
const NEW_PASSWORD = "PASTE_YOUR_NEW_PASSWORD_HERE";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

(async () => {
  const { data, error } = await supabase.auth.admin.listUsers();
  if (error) {
    console.error("Error listing users:", error.message);
    return;
  }
  const user = data.users.find((u) => u.email === EMAIL);
  if (!user) {
    console.error("No user found with that email.");
    return;
  }
  const { error: updateError } = await supabase.auth.admin.updateUserById(user.id, {
    password: NEW_PASSWORD,
  });
  if (updateError) {
    console.error("Failed:", updateError.message);
  } else {
    console.log("Password updated successfully. Log in with the new password now.");
  }
})();
