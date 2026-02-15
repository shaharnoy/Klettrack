import { hasSupabaseConfig } from "./supabaseClient.js";
import * as auth from "./auth.js";
import { currentRoute, navigate, onRouteChange } from "./router.js";
import { syncPull, syncPush } from "./syncApi.js";
import { createSyncStore } from "./state/store.js";
import { renderLoginView, renderRegisterView } from "./views/loginView.js";
import { renderCatalogView } from "./views/catalogView.js";
import { renderPlansView } from "./views/plansView.js";
import { renderAccountView } from "./views/accountView.js";
import { renderLogsView } from "./views/logsView.js";
import { renderDataManagerView } from "./views/dataManagerView.js";
import { renderConflictPanel } from "./components/conflictPanel.js";
import { showToast } from "./components/toasts.js";

const statusNode = document.getElementById("status");
const appViewNode = document.getElementById("app-view");
const syncOnboardingBannerNode = document.getElementById("sync-onboarding-banner");
const logoutButton = document.getElementById("logout-btn");
const syncButton = document.getElementById("sync-btn");
const getCurrentUser = auth.getCurrentUser;
const signInWithPassword = auth.signInWithPassword;
const signUpWithPassword =
  typeof auth.signUpWithPassword === "function"
    ? auth.signUpWithPassword
    : async () => {
        throw new Error("Registration is unavailable until the page cache refreshes.");
      };
const signOut = auth.signOut;
const requestPasswordReset =
  typeof auth.requestPasswordReset === "function"
    ? auth.requestPasswordReset
    : async () => {
        throw new Error("Password reset is unavailable until the page cache refreshes.");
      };
const updatePassword =
  typeof auth.updatePassword === "function"
    ? auth.updatePassword
    : async () => {
        throw new Error("Change password is unavailable until the page cache refreshes.");
      };
const deleteCurrentAccount =
  typeof auth.deleteCurrentAccount === "function"
    ? auth.deleteCurrentAccount
    : async () => {
        throw new Error("Account deletion is unavailable until the page cache refreshes.");
      };

const store = createSyncStore();
const defaultSelections = () => ({
  activityId: null,
  trainingTypeId: null,
  exerciseId: null,
  comboId: null,
  planId: null,
  planDayId: null,
  timerTemplateId: null,
  timerIntervalId: null,
  timerSessionId: null,
  metaSection: "day_types",
  metaItemId: null,
  metaSearch: "",
  planCloneOpen: false,
  planCloneName: "",
  planCloneStartDate: "",
  planSetupOpen: false,
  planSetupMode: "create",
  planAddDayOpen: false,
  planAddDayDate: "",
  planDayCloneOpen: false,
  planDayCloneMode: "clone",
  planDayCloneTargetDate: "",
  planDayCloneApplyRecurring: true,
  planDayRecurringWeekdays: [],
  logs: {
    mode: "all",
    source: "all",
    search: "",
    fromDate: "",
    toDate: "",
    gym: "",
    style: "",
    grade: "",
    climbType: "",
    onlyWip: false,
    sortColumn: "dateOnly",
    sortDirection: "desc"
  }
});

const state = {
  user: null,
  loginError: "",
  loginNotice: "",
  accountError: "",
  accountNotice: "",
  isSyncing: false,
  syncError: "",
  conflicts: [],
  pendingMutations: new Map(),
  conflictTelemetryEvents: [],
  hydratedUserId: null,
  cursor: null,
  selections: defaultSelections()
};

const realtimeEnabled =
  window.__SYNC_REALTIME_ENABLED__ === true || localStorage.getItem("SYNC_REALTIME_ENABLED") === "true";
let realtimeChannel = null;
let realtimePullTimeout = null;
let lastTrackedRoute = "";

if (logoutButton) {
  logoutButton.addEventListener("click", async () => {
    teardownRealtimeSubscription();
    await signOut();
    resetSessionState();
    navigate("/login");
    await render();
  });
}

if (syncButton) {
  syncButton.addEventListener("click", async () => {
    if (!state.user || state.isSyncing) {
      return;
    }
    try {
      setStatus("Syncing latest changes...", "syncing");
      await hydrateFromServer();
      await render();
      showToast("Sync complete", "success");
    } catch (error) {
      const message = friendlySyncErrorMessage(error);
      setStatus(`Sync error: ${message}`, "error");
      showToast(message, "error");
    }
  });
}

onRouteChange(render);
window.addEventListener("keydown", handleGlobalShortcuts);
void startApp();

async function startApp() {
  try {
    await restoreSession();
    await render();
  } catch (error) {
    renderFatalError(error);
  }
}

async function restoreSession() {
  if (!hasSupabaseConfig()) {
    setStatus("Missing Supabase config.", "error");
    return;
  }

  setStatus("Restoring session...", "syncing");
  try {
    state.user = await getCurrentUser();
  } catch {
    state.user = null;
  }
  if (state.user) {
    loadCursor(state.user.id);
  }
}

function canonicalRoute(route) {
  if (route === "/sessions" || route === "/climb-log") {
    return "/logs";
  }
  if (route === "/timers") {
    state.selections = {
      ...state.selections,
      metaSection: "timer_templates"
    };
    return "/data-manager";
  }
  return route;
}

async function render() {
  const rawRoute = currentRoute();
  const route = canonicalRoute(rawRoute);
  trackUXEvent("route_view", { route });

  if (!hasSupabaseConfig()) {
    updateSyncOnboardingBanner({ isAuthed: false });
    if (logoutButton) {
      logoutButton.classList.add("hidden");
    }
    if (syncButton) {
      syncButton.classList.add("hidden");
    }
    appViewNode.innerHTML = `
      <h2>Configuration Required</h2>
      <p>Add <code>SUPABASE_URL</code> and <code>SUPABASE_PUBLISHABLE_KEY</code> in localStorage or inject them into <code>window</code> before loading <code>/app.html</code>.</p>
    `;
    setStatus("Config missing", "error");
    return;
  }

  try {
    state.user = await getCurrentUser();
  } catch {
    state.user = null;
  }
  const isAuthed = Boolean(state.user);

  if (!isAuthed && route !== "/login" && route !== "/register") {
    teardownRealtimeSubscription();
    navigate("/login");
    return;
  }
  if (isAuthed && (route === "/login" || route === "/register")) {
    navigate("/catalog");
    return;
  }

  if (logoutButton) {
    logoutButton.classList.toggle("hidden", !isAuthed);
  }
  if (syncButton) {
    syncButton.classList.toggle("hidden", !isAuthed);
    syncButton.disabled = !isAuthed || state.isSyncing;
  }

  if (!isAuthed) {
    updateSyncOnboardingBanner({ isAuthed: false });
    teardownRealtimeSubscription();
    setStatus("Signed out", "info");
    if (route === "/register") {
      renderRegisterView({
        errorMessage: state.loginError,
        noticeMessage: state.loginNotice,
        onBackToLogin: () => {
          navigate("/login");
        },
        onSubmit: async (email, password) => {
          try {
            state.loginError = "";
            state.loginNotice = "";
            const payload = await signUpWithPassword(email, password);
            if (payload?.session?.access_token) {
              state.user = await getCurrentUser();
              if (state.user) {
                state.cursor = null;
                loadCursor(state.user.id);
                await hydrateFromServer();
                navigate("/catalog");
                return;
              }
            }
            state.loginNotice = "Account created. If email confirmation is enabled, check your inbox.";
          } catch (error) {
            state.loginError = normalizeAuthMessage(error, "Registration failed.");
          }
          await render();
        }
      });
      return;
    }
    renderLoginView({
      errorMessage: state.loginError,
      noticeMessage: state.loginNotice,
      onSubmit: async (identifier, password) => {
        try {
          state.loginError = "";
          state.loginNotice = "";
          await signInWithPassword(identifier, password);
          state.user = await getCurrentUser();
          if (!state.user) {
            state.loginError = "Sign in failed.";
            return;
          }
          state.cursor = null;
          loadCursor(state.user.id);
          await hydrateFromServer();
          navigate("/catalog");
        } catch (error) {
          state.loginError = normalizeAuthMessage(error, "Sign in failed.");
        }
        await render();
      },
      onForgotPassword: async (identifier) => {
        try {
          state.loginError = "";
          state.loginNotice = "";
          const redirectTo = `${window.location.origin}/app.html#/login`;
          await requestPasswordReset(identifier, redirectTo);
          showToast("Password reset email sent. Check your inbox.", "success");
        } catch (error) {
          state.loginError = normalizeAuthMessage(error, "Password reset request failed.");
        }
        await render();
      }
    });
    return;
  }

  if (state.hydratedUserId !== state.user.id) {
    store.reset();
    state.selections = defaultSelections();
    loadCursor(state.user.id);
    await hydrateFromServer();
    state.hydratedUserId = state.user.id;
  }

  ensureRealtimeSubscription();
  updateSyncOnboardingBanner({ isAuthed: true });

  if (rawRoute !== route) {
    navigate(route);
    return;
  }

  updateNav(route);
  renderConflictPanel(state.conflicts, {
    onKeepMine: async (conflict) => {
      await resolveConflictKeepMine(conflict);
    },
    onKeepServer: async (conflict) => {
      await resolveConflictKeepServer(conflict);
    }
  });

  if (route === "/catalog") {
    renderCatalogView({
      store,
      selection: state.selections,
      onSelect: (partial) => {
        state.selections = { ...state.selections, ...partial };
        void render();
      },
      onSave: async ({ entity, id, payload }) => {
        await executeMutationAction(async () => {
          await runMutation({ entity, id, type: "upsert", payload });
          await render();
        });
      },
      onSaveMany: async ({ mutations }) => {
        await executeMutationAction(async () => {
          await runMutationsBatch({ mutations });
          await render();
        });
      },
      onDelete: async ({ entity, id }) => {
        await executeMutationAction(async () => {
          await runMutation({ entity, id, type: "delete", payload: null });
          await render();
        });
      }
    });
    setStatus("Catalog ready", "ready");
    return;
  }

  if (route === "/data-manager") {
    renderDataManagerView({
      store,
      selection: state.selections,
      onSelect: (partial) => {
        state.selections = { ...state.selections, ...partial };
        void render();
      },
      onSave: async ({ entity, id, payload }) => {
        await executeMutationAction(async () => {
          await runMutation({ entity, id, type: "upsert", payload });
          await render();
        });
      },
      onDelete: async ({ entity, id }) => {
        await executeMutationAction(async () => {
          await runMutation({ entity, id, type: "delete", payload: null });
          await render();
        });
      }
    });
    setStatus("Data manager ready", "ready");
    return;
  }

  if (route === "/plans" || route.startsWith("/plans/")) {
    const routePlanId = route.startsWith("/plans/") ? route.split("/")[2] : null;
    if (routePlanId && routePlanId !== state.selections.planId) {
      state.selections.planId = routePlanId;
      state.selections.planDayId = null;
    }

    renderPlansView({
      store,
      selection: state.selections,
      onSelect: (partial) => {
        state.selections = { ...state.selections, ...partial };
        void render();
      },
      onSave: async ({ entity, id, payload }) => {
        await executeMutationAction(async () => {
          await runMutation({ entity, id, type: "upsert", payload });
          await render();
        });
      },
      onSaveMany: async ({ mutations }) => {
        await executeMutationAction(async () => {
          await runMutationsBatch({ mutations });
          await render();
        });
      },
      onSaveWithOutcome: async ({ entity, id, payload }) => {
        try {
          await runMutation({ entity, id, type: "upsert", payload });
          await render();
          return { ok: true };
        } catch (error) {
          const raw = error instanceof Error ? error.message : "unknown_error";
          const reason = raw.startsWith("Push failed: ") ? raw.slice("Push failed: ".length) : raw;
          return {
            ok: false,
            reason,
            message: friendlySyncErrorMessage(error)
          };
        }
      },
      onDelete: async ({ entity, id }) => {
        await executeMutationAction(async () => {
          await runMutation({ entity, id, type: "delete", payload: null });
          await render();
        });
      },
      onOpenPlan: (planId) => {
        navigate(`/plans/${planId}`);
      }
    });
    setStatus("Training plans ready", "ready");
    return;
  }

  if (route === "/logs") {
    renderLogsView({
      store,
      filters: state.selections.logs,
      onFiltersChange: (nextFilters) => {
        state.selections = {
          ...state.selections,
          logs: {
            ...state.selections.logs,
            ...nextFilters
          }
        };
        void render();
      }
    });
    setStatus("Logs ready", "ready");
    return;
  }

  if (route === "/account") {
    renderAccountView({
      user: state.user,
      errorMessage: state.accountError,
      noticeMessage: state.accountNotice,
      onChangePassword: async (newPassword) => {
        try {
          state.accountError = "";
          state.accountNotice = "";
          await updatePassword(newPassword);
          state.accountNotice = "Password updated successfully.";
          showToast("Password updated.", "success");
        } catch (error) {
          state.accountError = normalizeAuthMessage(error, "Password update failed.");
        }
        await render();
      },
      onDeleteAccount: async () => {
        const confirmed = window.confirm(
          "This permanently deletes your cloud account and cloud-synced data. Local app data on your device remains unless you remove the app. Continue?"
        );
        if (!confirmed) {
          return;
        }
        try {
          state.accountError = "";
          state.accountNotice = "";
          await deleteCurrentAccount();
          await signOut();
          resetSessionState();
          navigate("/login");
          showToast("Account deleted.", "info");
        } catch (error) {
          state.accountError = normalizeAuthMessage(error, "Account deletion failed.");
        }
        await render();
      }
    });
    setStatus("Account settings", "ready");
    return;
  }

  navigate("/catalog");
}

async function hydrateFromServer({ allowCursorRecovery = true } = {}) {
  if (!state.user) {
    return;
  }

  state.isSyncing = true;
  state.syncError = "";
  if (syncButton) {
    syncButton.disabled = true;
  }
  setStatus("Syncing...", "syncing");
  const startCursor = state.cursor;
  let totalPulledChanges = 0;

  try {
    let hasMore = true;
    while (hasMore) {
      const pullResponse = await syncPull({ cursor: state.cursor, limit: 200 });
      totalPulledChanges += Array.isArray(pullResponse.changes) ? pullResponse.changes.length : 0;
      store.applyPullChanges(pullResponse.changes);
      state.cursor = pullResponse.nextCursor;
      hasMore = Boolean(pullResponse.hasMore);
      persistCursor(state.user.id, state.cursor);
    }

    if (allowCursorRecovery && startCursor && totalPulledChanges === 0 && hasNoHydratedData(store)) {
      clearCursor(state.user.id);
      state.cursor = null;
      trackUXEvent("cursor_recovery_retry", { reason: "empty_pull_with_existing_cursor" });
      await hydrateFromServer({ allowCursorRecovery: false });
      return;
    }
  } catch (error) {
    state.syncError = error instanceof Error ? error.message : "Sync failed.";
    showToast(state.syncError, "error");
  } finally {
    state.isSyncing = false;
    if (syncButton) {
      syncButton.disabled = false;
    }
    if (state.syncError) {
      setStatus(`Sync error: ${state.syncError}`, "error");
    } else {
      setStatus(`Signed in as ${state.user.email || "user"}`, "ready");
    }
  }
}

async function runMutation({ entity, id, type, payload }) {
  if (!state.user) {
    throw new Error("Missing auth session.");
  }

  const baseVersion = store.version(entity, id);

  const opId = crypto.randomUUID();
  trackUXEvent("mutation_start", { entity, type });
  const mutation = {
    opId,
    entity,
    entityId: id,
    type,
    baseVersion,
    updatedAtClient: new Date().toISOString(),
    payload
  };
  state.pendingMutations.set(opId, mutation);

  const pushResponse = await syncPush({
    deviceId: getDeviceId(),
    baseCursor: state.cursor,
    mutations: [mutation]
  });

  releaseHandledPendingMutations(pushResponse);
  state.conflicts = Array.isArray(pushResponse.conflicts) ? pushResponse.conflicts : [];
  const failed = Array.isArray(pushResponse.failed) ? pushResponse.failed : [];
  for (const conflict of state.conflicts) {
    recordConflictTelemetryEvent("detected", conflict);
  }

  if (failed.length > 0) {
    const reason = String(failed[0]?.reason || "unknown_error");
    trackUXEvent("mutation_failed", { entity, type, reason });
    throw new Error(`Push failed: ${reason}`);
  }

  if (state.conflicts.length > 0) {
    trackUXEvent("mutation_conflict", { entity, type, conflictCount: state.conflicts.length });
    setStatus(`${state.conflicts.length} sync conflict(s) need review`, "warning");
    showToast(`${state.conflicts.length} sync conflict(s)`, "error");
  } else {
    trackUXEvent("mutation_succeeded", { entity, type });
    setStatus("All changes synced", "ready");
  }

  await hydrateFromServer();
}

async function runMutationsBatch({ mutations }) {
  if (!state.user) {
    throw new Error("Missing auth session.");
  }
  if (!Array.isArray(mutations) || mutations.length === 0) {
    return;
  }

  const preparedMutations = mutations.map((mutation) => {
    const opId = crypto.randomUUID();
    const entity = mutation.entity;
    const entityId = mutation.id;
    const type = mutation.type || "upsert";
    const payload = mutation.payload ?? null;
    const prepared = {
      opId,
      entity,
      entityId,
      type,
      baseVersion: store.version(entity, entityId),
      updatedAtClient: new Date().toISOString(),
      payload
    };
    state.pendingMutations.set(opId, prepared);
    return prepared;
  });

  trackUXEvent("mutation_batch_start", { count: preparedMutations.length });
  const pushResponse = await syncPush({
    deviceId: getDeviceId(),
    baseCursor: state.cursor,
    mutations: preparedMutations
  });

  releaseHandledPendingMutations(pushResponse);
  state.conflicts = Array.isArray(pushResponse.conflicts) ? pushResponse.conflicts : [];
  const failed = Array.isArray(pushResponse.failed) ? pushResponse.failed : [];
  for (const conflict of state.conflicts) {
    recordConflictTelemetryEvent("detected", conflict);
  }

  if (failed.length > 0) {
    const reason = String(failed[0]?.reason || "unknown_error");
    trackUXEvent("mutation_batch_failed", { count: preparedMutations.length, reason });
    throw new Error(`Push failed: ${reason}`);
  }

  if (state.conflicts.length > 0) {
    trackUXEvent("mutation_batch_conflict", { count: preparedMutations.length, conflictCount: state.conflicts.length });
    setStatus(`${state.conflicts.length} sync conflict(s) need review`, "warning");
    showToast(`${state.conflicts.length} sync conflict(s)`, "error");
  } else {
    trackUXEvent("mutation_batch_succeeded", { count: preparedMutations.length });
    setStatus("All changes synced", "ready");
  }

  await hydrateFromServer();
}

async function resolveConflictKeepMine(conflict) {
  trackUXEvent("conflict_keep_mine_start", { entity: conflict.entity });
  const pending = state.pendingMutations.get(conflict.opId);
  if (!pending) {
    throw new Error("Cannot Keep Mine: original mutation not found.");
  }

  const rebasedOpId = crypto.randomUUID();
  const rebasedMutation = {
    ...pending,
    opId: rebasedOpId,
    baseVersion: Number.isFinite(conflict.serverVersion) ? Number(conflict.serverVersion) : pending.baseVersion,
    updatedAtClient: new Date().toISOString()
  };

  state.pendingMutations.delete(conflict.opId);
  state.pendingMutations.set(rebasedOpId, rebasedMutation);

  const pushResponse = await syncPush({
    deviceId: getDeviceId(),
    baseCursor: state.cursor,
    mutations: [rebasedMutation]
  });

  releaseHandledPendingMutations(pushResponse);
  const nextConflicts = Array.isArray(pushResponse.conflicts) ? pushResponse.conflicts : [];
  state.conflicts = replaceConflict(state.conflicts, conflict.opId, nextConflicts);
  recordConflictTelemetryEvent("keep_mine", conflict);
  trackUXEvent("conflict_keep_mine_done", { entity: conflict.entity });
  for (const nextConflict of nextConflicts) {
    recordConflictTelemetryEvent("detected", nextConflict);
  }
  await hydrateFromServer();
  await render();
}

async function resolveConflictKeepServer(conflict) {
  trackUXEvent("conflict_keep_server_start", { entity: conflict.entity });
  state.pendingMutations.delete(conflict.opId);
  state.conflicts = state.conflicts.filter((item) => item.opId !== conflict.opId);
  recordConflictTelemetryEvent("keep_server", conflict);
  trackUXEvent("conflict_keep_server_done", { entity: conflict.entity });
  await hydrateFromServer();
  await render();
}

async function executeMutationAction(action) {
  try {
    await action();
  } catch (error) {
    const message = friendlySyncErrorMessage(error);
    trackUXEvent("mutation_action_error", { message });
    setStatus(`Sync error: ${message}`, "error");
    showToast(message, "error");
  }
}

function updateNav(route) {
  const links = document.querySelectorAll(".nav-link[data-route]");
  for (const link of links) {
    const targetRoute = link.dataset.route || "";
    const isActive = routeMatches(route, targetRoute);
    link.classList.toggle("active", isActive);
    if (isActive) {
      link.setAttribute("aria-current", "page");
    } else {
      link.removeAttribute("aria-current");
    }
  }
}

function routeMatches(route, targetRoute) {
  if (!route || !targetRoute) {
    return false;
  }
  return route === targetRoute || route.startsWith(`${targetRoute}/`);
}

function resetSessionState() {
  store.reset();
  state.user = null;
  state.loginError = "";
  state.loginNotice = "";
  state.accountError = "";
  state.accountNotice = "";
  state.isSyncing = false;
  state.syncError = "";
  state.conflicts = [];
  state.pendingMutations = new Map();
  state.conflictTelemetryEvents = [];
  state.hydratedUserId = null;
  state.cursor = null;
  state.selections = defaultSelections();
}

function normalizeAuthMessage(error, fallback) {
  const raw = error instanceof Error ? error.message : fallback;
  const normalized = String(raw || "").toLowerCase();
  if (normalized.includes("email not confirmed")) {
    return "Please confirm your email address before signing in.";
  }
  if (normalized.includes("invalid login credentials")) {
    return "Invalid email/username or password.";
  }
  return raw || fallback;
}

function releaseHandledPendingMutations(pushResponse) {
  const acknowledged = Array.isArray(pushResponse.acknowledgedOpIds) ? pushResponse.acknowledgedOpIds : [];
  const failed = Array.isArray(pushResponse.failed) ? pushResponse.failed : [];

  for (const opId of acknowledged) {
    state.pendingMutations.delete(opId);
  }

  for (const failure of failed) {
    if (failure?.opId) {
      state.pendingMutations.delete(failure.opId);
    }
  }
}

function replaceConflict(currentConflicts, resolvedOpId, appendedConflicts) {
  const kept = currentConflicts.filter((item) => item.opId !== resolvedOpId);
  return [...kept, ...appendedConflicts];
}

function recordConflictTelemetryEvent(type, conflict) {
  const event = {
    id: crypto.randomUUID(),
    type,
    at: new Date().toISOString(),
    entity: conflict.entity,
    entityId: conflict.entityId,
    reason: conflict.reason
  };
  state.conflictTelemetryEvents.unshift(event);
  if (state.conflictTelemetryEvents.length > 100) {
    state.conflictTelemetryEvents.length = 100;
  }
  persistConflictAuditEvent(event);

  console.info("[sync-conflict]", event);
}

function persistConflictAuditEvent(event) {
  const key = "sync_conflict_audit_events";
  let safeList = [];
  try {
    const existing = JSON.parse(localStorage.getItem(key) || "[]");
    safeList = Array.isArray(existing) ? existing : [];
  } catch {
    safeList = [];
  }
  safeList.unshift(event);
  if (safeList.length > 200) {
    safeList.length = 200;
  }
  localStorage.setItem(key, JSON.stringify(safeList));
}

function friendlySyncErrorMessage(error) {
  if (!(error instanceof Error)) {
    return "Sync failed. Please try again.";
  }
  const message = String(error.message || "").toLowerCase();
  if (message.includes("missing auth session") || message.includes("auth")) {
    return "Your session expired. Please sign in again.";
  }
  if (message.includes("version_mismatch") || message.includes("conflict")) {
    return "This item changed elsewhere. Resolve the conflict and retry.";
  }
  if (message.includes("network") || message.includes("fetch")) {
    return "Network issue during sync. Retry when connection is stable.";
  }
  if (message.includes("invalid")) {
    return "Server rejected this update due to invalid data.";
  }
  return "Sync failed. Please try again.";
}

function ensureRealtimeSubscription() {
  if (!realtimeEnabled || !state.user || realtimeChannel) {
    return;
  }
  // Realtime channel subscription depends on supabase-js runtime client.
  // Web now uses REST auth/session to avoid external module load failures,
  // so keep pull-based sync as the reliable default.
}

function teardownRealtimeSubscription() {
  if (realtimePullTimeout) {
    clearTimeout(realtimePullTimeout);
    realtimePullTimeout = null;
  }
  realtimeChannel = null;
}

function handleRealtimeChange() {
  if (!state.user) {
    return;
  }
  if (realtimePullTimeout) {
    clearTimeout(realtimePullTimeout);
  }
  realtimePullTimeout = setTimeout(async () => {
    realtimePullTimeout = null;
    await hydrateFromServer();
    await render();
  }, 750);
}

void handleRealtimeChange;

function getDeviceId() {
  const key = "web_sync_device_id";
  const existing = localStorage.getItem(key);
  if (existing) {
    return existing;
  }

  const value = crypto.randomUUID();
  localStorage.setItem(key, value);
  return value;
}

function cursorKey(userId) {
  return `web_sync_cursor:${userId}`;
}

function persistCursor(userId, cursor) {
  if (!cursor) {
    return;
  }
  localStorage.setItem(cursorKey(userId), cursor);
}

function loadCursor(userId) {
  state.cursor = localStorage.getItem(cursorKey(userId));
}

function clearCursor(userId) {
  localStorage.removeItem(cursorKey(userId));
}

function hasNoHydratedData(storeRef) {
  const entities = [
    "plans",
    "plan_days",
    "activities",
    "training_types",
    "exercises",
    "sessions",
    "session_items",
    "timer_templates",
    "timer_intervals",
    "climb_entries"
  ];
  return entities.every((entity) => storeRef.active(entity).length === 0);
}

function hasCatalogData(storeRef) {
  const catalogEntities = [
    "activities",
    "training_types",
    "exercises",
    "boulder_combinations",
    "boulder_combination_exercises"
  ];
  return catalogEntities.some((entity) => storeRef.active(entity).length > 0);
}

function updateSyncOnboardingBanner({ isAuthed }) {
  if (!syncOnboardingBannerNode) {
    return;
  }
  const showBanner = Boolean(isAuthed && !hasCatalogData(store));
  if (!showBanner) {
    syncOnboardingBannerNode.classList.add("hidden");
    syncOnboardingBannerNode.textContent = "";
    statusNode?.classList.remove("hidden");
    return;
  }

  syncOnboardingBannerNode.classList.remove("hidden");
  syncOnboardingBannerNode.innerHTML =
    "<strong>Data not synced yet.</strong> New accounts start empty on web. Open the iOS app, sign in with the same account, and run sync to bring data here.";
  statusNode?.classList.add("hidden");
}

function setStatus(text, tone = "info") {
  if (!statusNode) {
    return;
  }

  statusNode.textContent = text;
  statusNode.dataset.statusTone = tone;
}

function trackUXEvent(name, payload = {}) {
  try {
    if (name === "route_view") {
      const route = String(payload.route || "");
      if (route === lastTrackedRoute) {
        return;
      }
      lastTrackedRoute = route;
    }

    const event = {
      id: safeRandomID(),
      name,
      at: new Date().toISOString(),
      ...payload
    };

    const key = "web_ux_telemetry_events";
    let safeList = [];
    try {
      const existing = JSON.parse(localStorage.getItem(key) || "[]");
      safeList = Array.isArray(existing) ? existing : [];
    } catch {
      safeList = [];
    }

    safeList.unshift(event);
    if (safeList.length > 250) {
      safeList.length = 250;
    }

    try {
      localStorage.setItem(key, JSON.stringify(safeList));
    } catch {
      // Ignore storage write failures (private mode, quota, policy).
    }

    console.info("[web-ux]", event);
  } catch {
    // Telemetry must never break app behavior.
  }
}

function safeRandomID() {
  const randomUUID = globalThis.crypto?.randomUUID;
  if (typeof randomUUID === "function") {
    return randomUUID.call(globalThis.crypto);
  }
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function handleGlobalShortcuts(event) {
  const tagName = String(event.target?.tagName || "").toLowerCase();
  if (tagName === "input" || tagName === "textarea" || event.target?.isContentEditable) {
    return;
  }

  if (event.key === "/" && !event.altKey && !event.metaKey && !event.ctrlKey) {
    const searchInput = document.querySelector("input[type='search']");
    if (searchInput) {
      event.preventDefault();
      searchInput.focus();
      searchInput.select?.();
    }
    return;
  }

  if (!event.altKey || event.metaKey || event.ctrlKey) {
    return;
  }

  const routeByDigit = {
    "1": "/catalog",
    "2": "/data-manager",
    "3": "/plans",
    "4": "/logs",
    "5": "/account"
  };
  const route = routeByDigit[event.key];
  if (!route) {
    return;
  }
  event.preventDefault();
  navigate(route);
}

function renderFatalError(error) {
  const message = error instanceof Error ? error.message : "Unknown startup error";
  setStatus("App failed to initialize", "error");
  if (!appViewNode) {
    return;
  }
  appViewNode.innerHTML = `
    <h2>Web App Error</h2>
    <p class="error">Unable to initialize the app: ${escapeHTML(message)}</p>
    <p class="muted">Open browser console for details, then reload this page.</p>
  `;
}

function escapeHTML(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
