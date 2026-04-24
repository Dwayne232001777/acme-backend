export function PreferencesPanel() {
  return (
    <form>
      <label htmlFor="theme">Theme</label>
      <select id="theme" name="theme" aria-label="Select theme">
        <option>Light</option>
        <option>Dark</option>
      </select>
      <label htmlFor="tz">Timezone</label>
      <input id="tz" type="text" aria-label="Timezone" />
    </form>
  );
}
