const THEME_STORAGE_KEY = "WEB_THEME";
const rootElement = document.documentElement;
const themeButton = document.getElementById("theme-btn");
const themeIcon = document.getElementById("theme-icon");

const storedTheme = localStorage.getItem(THEME_STORAGE_KEY);
const initialTheme =
  storedTheme === "light" || storedTheme === "dark"
    ? storedTheme
    : (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
applyTheme(initialTheme);

themeButton?.addEventListener("click", () => {
  const nextTheme = rootElement.dataset.theme === "dark" ? "light" : "dark";
  applyTheme(nextTheme);
  localStorage.setItem(THEME_STORAGE_KEY, nextTheme);
});

function applyTheme(theme) {
  rootElement.dataset.theme = theme;
  if (!themeIcon || !themeButton) {
    return;
  }
  const isDark = theme === "dark";
  themeIcon.innerHTML = isDark
    ? '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="4"/><path d="M12 2v2.2"/><path d="M12 19.8V22"/><path d="M4.9 4.9l1.6 1.6"/><path d="M17.5 17.5l1.6 1.6"/><path d="M2 12h2.2"/><path d="M19.8 12H22"/><path d="M4.9 19.1l1.6-1.6"/><path d="M17.5 6.5l1.6-1.6"/></svg>'
    : '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M20 14.2A8 8 0 1 1 9.8 4a7 7 0 1 0 10.2 10.2z"/></svg>';
  const nextLabel = isDark ? "Switch to light theme" : "Switch to dark theme";
  themeButton.setAttribute("aria-label", nextLabel);
  themeButton.setAttribute("title", nextLabel);
}

window.__SUPABASE_URL__ = window.__SUPABASE_URL__ || localStorage.getItem("SUPABASE_URL") || "";
window.__SUPABASE_PUBLISHABLE_KEY__ = window.__SUPABASE_PUBLISHABLE_KEY__ || localStorage.getItem("SUPABASE_PUBLISHABLE_KEY") || "";
window.__USERNAME_RESOLVER_URL__ = window.__USERNAME_RESOLVER_URL__ || localStorage.getItem("SUPABASE_USERNAME_RESOLVER_URL") || "";
window.__SYNC_REALTIME_ENABLED__ = window.__SYNC_REALTIME_ENABLED__ || localStorage.getItem("SYNC_REALTIME_ENABLED") === "true";
