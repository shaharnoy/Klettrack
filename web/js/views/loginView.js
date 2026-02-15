export function renderLoginView({ onSubmit, onForgotPassword, errorMessage, noticeMessage }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  root.innerHTML = `
    <h2>Welcome</h2>
    <p>Sign in with an account created in the iOS app. Account signup is available only in the app.</p>

    <form id="login-form" class="row" style="flex-direction: column; align-items: stretch; max-width: 420px;">
      <input id="identifier" class="input" type="text" placeholder="Email or username" autocomplete="username" required />
      <input id="password" class="input" type="password" placeholder="Password" autocomplete="current-password" required />
      <button class="btn primary" type="submit">Sign In</button>
      <button id="open-forgot-password" class="btn" type="button">Forgot password?</button>
    </form>

    <form id="forgot-password-form" class="row hidden" style="flex-direction: column; align-items: stretch; max-width: 420px;">
      <input id="forgot-identifier" class="input" type="text" placeholder="Email or username" autocomplete="username" required />
      <button class="btn primary" type="submit">Send Reset Email</button>
      <button id="close-forgot-password" class="btn" type="button">Back to Sign In</button>
    </form>

    <p id="login-notice" class="muted">${noticeMessage ? escapeHTML(noticeMessage) : ""}</p>
    <p id="login-error" class="error">${errorMessage ? escapeHTML(errorMessage) : ""}</p>
  `;

  const form = document.getElementById("login-form");
  const identifierInput = document.getElementById("identifier");
  const passwordInput = document.getElementById("password");
  const forgotPasswordForm = document.getElementById("forgot-password-form");
  const forgotIdentifierInput = document.getElementById("forgot-identifier");
  const openForgotPasswordButton = document.getElementById("open-forgot-password");
  const closeForgotPasswordButton = document.getElementById("close-forgot-password");
  const errorNode = document.getElementById("login-error");
  const noticeNode = document.getElementById("login-notice");
  let showForgotPassword = false;
  openForgotPasswordButton?.addEventListener("click", () => {
    showForgotPassword = true;
    form?.classList.add("hidden");
    forgotPasswordForm?.classList.remove("hidden");
    if (identifierInput && forgotIdentifierInput) {
      forgotIdentifierInput.value = identifierInput.value.trim();
    }
    if (errorNode) {
      errorNode.textContent = "";
    }
    if (noticeNode) {
      noticeNode.textContent = "";
    }
  });
  closeForgotPasswordButton?.addEventListener("click", () => {
    showForgotPassword = false;
    forgotPasswordForm?.classList.add("hidden");
    form?.classList.remove("hidden");
    if (errorNode) {
      errorNode.textContent = "";
    }
  });

  form?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (showForgotPassword) {
      return;
    }
    if (!identifierInput || !passwordInput) {
      return;
    }

    const identifier = identifierInput.value.trim();
    const password = passwordInput.value;

    if (!identifier || !password) {
      if (errorNode) {
        errorNode.textContent = "Please enter both identifier and password.";
      }
      return;
    }

    if (errorNode) {
      errorNode.textContent = "";
    }
    if (noticeNode) {
      noticeNode.textContent = "";
    }
    await onSubmit(identifier, password);
  });

  forgotPasswordForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!forgotIdentifierInput) {
      return;
    }
    const identifier = forgotIdentifierInput.value.trim();
    if (!identifier) {
      if (errorNode) {
        errorNode.textContent = "Please enter your email or username.";
      }
      return;
    }
    if (errorNode) {
      errorNode.textContent = "";
    }
    if (noticeNode) {
      noticeNode.textContent = "";
    }
    await onForgotPassword(identifier);
  });
}

export function renderRegisterView({ onSubmit, onBackToLogin, errorMessage, noticeMessage }) {
  const root = document.getElementById("app-view");
  if (!root) {
    return;
  }

  root.innerHTML = `
    <h2>Create Account</h2>
    <p>This registration page is intended to be opened from the iOS app.</p>

    <form id="register-form" class="row" style="flex-direction: column; align-items: stretch; max-width: 420px;">
      <input id="register-email" class="input" type="email" placeholder="Email" autocomplete="email" required />
      <input id="register-password" class="input" type="password" placeholder="Password" autocomplete="new-password" required />
      <button class="btn primary" type="submit">Create Account</button>
      <button id="back-to-login" class="btn" type="button">Back to Sign In</button>
    </form>

    <p id="register-notice" class="muted">${noticeMessage ? escapeHTML(noticeMessage) : ""}</p>
    <p id="register-error" class="error">${errorMessage ? escapeHTML(errorMessage) : ""}</p>
  `;

  const form = document.getElementById("register-form");
  const emailInput = document.getElementById("register-email");
  const passwordInput = document.getElementById("register-password");
  const errorNode = document.getElementById("register-error");
  const noticeNode = document.getElementById("register-notice");

  document.getElementById("back-to-login")?.addEventListener("click", () => {
    onBackToLogin();
  });

  form?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!emailInput || !passwordInput) {
      return;
    }
    const email = emailInput.value.trim();
    const password = passwordInput.value;
    if (!email || !password) {
      if (errorNode) {
        errorNode.textContent = "Please enter email and password.";
      }
      return;
    }
    if (errorNode) {
      errorNode.textContent = "";
    }
    if (noticeNode) {
      noticeNode.textContent = "";
    }
    await onSubmit(email, password);
  });
}

function escapeHTML(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}
