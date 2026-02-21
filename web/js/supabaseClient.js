export const supabaseURL = (window.__SUPABASE_URL__ || "").trim();
export const supabaseKey = (window.__SUPABASE_PUBLISHABLE_KEY__ || "").trim();

export function hasSupabaseConfig() {
  return Boolean(supabaseURL) && Boolean(supabaseKey);
}
