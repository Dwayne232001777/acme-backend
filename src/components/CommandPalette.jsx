import React, { useState, useEffect } from "react";
const ACTIONS = [
  { id: "new-task", label: "Create new task" },
  { id: "search", label: "Search everything" },
  { id: "settings", label: "Open settings" },
];
export function CommandPalette() {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    function k(e) {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") { e.preventDefault(); setOpen(p => !p); }
      if (e.key === "Escape") setOpen(false);
    }
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, []);
  if (!open) return null;
  return <div className="palette">{ACTIONS.map(a => <div key={a.id}>{a.label}</div>)}</div>;
}
