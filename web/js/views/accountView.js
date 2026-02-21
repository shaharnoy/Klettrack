import { renderWorkspaceShell } from "../components/workspaceLayout.js";

export function renderAccountView({ user, onChangePassword, onDeleteAccount, errorMessage = "", noticeMessage = "" }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  root.innerHTML = renderWorkspaceShell({
    title: "Account",
    description: "Manage your account credentials and account lifecycle.",
    pills: ["auth", "user"],
    bodyHTML: `
      <div class="workspace-grid" style="grid-template-columns: 1fr 1fr;">
        <section class="pane">
          <h3>Profile</h3>
          <p class="muted">Signed in as</p>
          <p><strong>${escapeHTML(user?.email || "Unknown user")}</strong></p>
        </section>

        <section class="pane">
          <h3>Change Password</h3>
          <form id="change-password-form" class="editor-form compact">
            <label>New Password
              <input id="new-password" class="input" type="password" autocomplete="new-password" placeholder="Minimum 6 characters" required />
            </label>
            <label>Confirm New Password
              <input id="new-password-confirm" class="input" type="password" autocomplete="new-password" required />
            </label>
            <button class="btn primary" type="submit">Update Password</button>
          </form>
        </section>
      </div>

      <section class="pane">
        <h3>Delete Account</h3>
        <p class="muted">This permanently deletes your cloud account and cloud-synced data. Local app data on your device remains unless you delete the app.</p>
        <form id="delete-account-form" class="editor-form compact">
          <label>Type <code>DELETE</code> to confirm
            <input id="delete-account-confirm-text" class="input" type="text" autocomplete="off" placeholder="DELETE" required />
          </label>
          <button class="btn destructive" type="submit">
            <span class="icon-trash" aria-hidden="true"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></span>
            <span>Delete My Account</span>
          </button>
        </form>
      </section>

      <p id="account-notice" class="muted">${noticeMessage ? escapeHTML(noticeMessage) : ""}</p>
      <p id="account-error" class="error">${errorMessage ? escapeHTML(errorMessage) : ""}</p>
    `
  });

  const errorNode = document.getElementById("account-error");
  const noticeNode = document.getElementById("account-notice");

  document.getElementById("change-password-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const password = String(document.getElementById("new-password")?.value || "");
    const confirm = String(document.getElementById("new-password-confirm")?.value || "");

    if (!password || !confirm) {
      if (errorNode) {
        errorNode.textContent = "Please complete both password fields.";
      }
      return;
    }
    if (password.length < 6) {
      if (errorNode) {
        errorNode.textContent = "Password must be at least 6 characters.";
      }
      return;
    }
    if (password !== confirm) {
      if (errorNode) {
        errorNode.textContent = "Password confirmation does not match.";
      }
      return;
    }

    if (errorNode) {
      errorNode.textContent = "";
    }
    if (noticeNode) {
      noticeNode.textContent = "";
    }
    await onChangePassword(password);
  });

  document.getElementById("delete-account-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const confirmation = String(document.getElementById("delete-account-confirm-text")?.value || "").trim();
    if (confirmation !== "DELETE") {
      if (errorNode) {
        errorNode.textContent = "Type DELETE exactly to confirm account deletion.";
      }
      return;
    }

    if (errorNode) {
      errorNode.textContent = "";
    }
    if (noticeNode) {
      noticeNode.textContent = "";
    }
    await onDeleteAccount();
  });
}

function escapeHTML(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
