let container = null;

export function showToast(message, type = "info", action = null) {
  ensureContainer();
  const node = document.createElement("div");
  node.className = `toast ${type}`;
  const content = document.createElement("div");
  content.textContent = message;
  node.append(content);

  if (action?.label && typeof action.onClick === "function") {
    const actionButton = document.createElement("button");
    actionButton.type = "button";
    actionButton.className = "btn";
    actionButton.textContent = action.label;
    actionButton.addEventListener("click", async () => {
      try {
        await action.onClick();
      } finally {
        node.remove();
      }
    });
    node.append(actionButton);
  }
  container.append(node);

  const timeoutID = setTimeout(() => {
    node.classList.add("hide");
    setTimeout(() => node.remove(), 220);
  }, 2400);

  if (action?.label) {
    node.addEventListener("mouseenter", () => clearTimeout(timeoutID), { once: true });
  }
}

function ensureContainer() {
  if (container) {
    return;
  }

  container = document.createElement("div");
  container.id = "toast-root";
  document.body.append(container);
}
