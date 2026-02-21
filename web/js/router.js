export function currentRoute() {
  const hash = window.location.hash || "#/login";
  const [path] = hash.slice(1).split("?");
  return path || "/login";
}

export function navigate(route) {
  const target = route.startsWith("#") ? route : `#${route}`;
  if (window.location.hash === target) {
    window.dispatchEvent(new HashChangeEvent("hashchange"));
    return;
  }
  window.location.hash = target;
}

export function onRouteChange(handler) {
  window.addEventListener("hashchange", handler);
}
