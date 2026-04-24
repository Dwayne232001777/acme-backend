export function installKeyboardNav(container) {
  const focusable = container.querySelectorAll("button, [href], input, select, textarea, [tabindex]:not([tabindex=\\"-1\\"])");
  container.addEventListener("keydown", (e) => {
    if (e.key === "Tab") return;
    if (e.key === "Escape") container.dispatchEvent(new CustomEvent("close"));
  });
  return focusable;
}
