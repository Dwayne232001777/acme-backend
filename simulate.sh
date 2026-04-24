#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  simulate.sh — Long-running simulation of team activity on the
#  Acme Backend repo. Exercises every TeamFlow feature:
#
#    • Commits from multiple authors (credits commit author, not pusher)
#    • Issues opened on GitHub (auto-creates TeamFlow tasks)
#    • Issue comments and closes (exercises event polling)
#    • Branch creation (CreateEvent)
#    • Mix of subtask-matching and unrelated commits
#
#  Runs ~70 events by default with randomized 10-30s intervals.
#
#  Usage:
#    ./simulate.sh              # full run, random 10-30s delays (~25 min)
#    ./simulate.sh --fast       # 5s fixed delay (~6 min)
#    ./simulate.sh --instant    # no delay (burst mode for testing)
#    ./simulate.sh --step       # wait for Enter between events
#    ./simulate.sh --loop N     # repeat the whole sequence N times
#    ./simulate.sh --skip-issues  # commits only (for offline demos)
#
#  Requirements:
#    • Run from inside the dummy repo's working tree
#    • Remote 'origin' points to a GitHub repo you can push to
#    • For issue events: either `gh auth login` OR GITHUB_TOKEN env var
# ─────────────────────────────────────────────────────────────────

set -e

# ── Args ──────────────────────────────────────────────────────────
MODE="random"      # random | fast | instant | step
LOOPS=1
SKIP_ISSUES=false

while [ $# -gt 0 ]; do
    case "$1" in
        --fast)         MODE="fast" ;;
        --instant)      MODE="instant" ;;
        --step)         MODE="step" ;;
        --skip-issues)  SKIP_ISSUES=true ;;
        --loop)         shift; LOOPS="$1" ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
    shift
done

# ── Colours ───────────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
GREY='\033[0;90m'
RESET='\033[0m'

# ── Pre-flight ────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo -e "${RED}ERROR:${RESET} Run this script from inside the git repo."
    exit 1
fi
if ! git remote get-url origin &>/dev/null; then
    echo -e "${RED}ERROR:${RESET} No 'origin' remote configured."
    exit 1
fi

REPO_SLUG=$(git remote get-url origin | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#' | sed 's/\.git$//')

HAS_GH=false
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    HAS_GH=true
fi

if [ "$SKIP_ISSUES" = false ] && [ "$HAS_GH" = false ] && [ -z "${GITHUB_TOKEN:-}" ]; then
    echo -e "${YELLOW}WARNING:${RESET} No 'gh' CLI auth and no GITHUB_TOKEN — issue events will be skipped."
    echo -e "${GREY}  To enable: run 'gh auth login' OR export GITHUB_TOKEN=ghp_...${RESET}"
    SKIP_ISSUES=true
fi

# ── State ─────────────────────────────────────────────────────────
event_count=0
opened_issue_numbers=()   # issue numbers we've opened, so we can close them later

# ── Helpers ───────────────────────────────────────────────────────
wait_between() {
    if [ "$event_count" -eq 0 ]; then return; fi
    case "$MODE" in
        instant) return ;;
        fast)    sleep 5 ;;
        step)    echo ""; read -p "  Press Enter for next event..." ;;
        random)
            local delay=$((RANDOM % 21 + 10))  # 10-30s
            echo -e "${GREY}  ⏱  Next event in ${delay}s…${RESET}"
            sleep "$delay"
            ;;
    esac
}

header() {
    event_count=$((event_count + 1))
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  Event ${event_count}${RESET} — $1"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}"
}

# do_commit <author_name> <author_email> <message> <note> <file_path> <file_content>
do_commit() {
    local author_name="$1" author_email="$2" message="$3"
    local note="$4" file_path="$5" file_content="$6"

    wait_between
    header "💾 Commit by ${author_name}"
    echo -e "${YELLOW}  Message:${RESET} $(echo "$message" | head -n1)"
    if [ -n "$note" ]; then echo -e "${GREY}  ↳ ${note}${RESET}"; fi

    mkdir -p "$(dirname "$file_path")"
    echo "$file_content" > "$file_path"

    git add -A
    git commit --author="${author_name} <${author_email}>" -m "$message" --quiet
    git push --quiet

    echo -e "${GREEN}  ✓ Pushed${RESET}"
}

# do_noop_commit <author_name> <author_email> <message> <note>
# A small chore commit that shouldn't match any subtask — exercises the
# matcher's "return []" behaviour.
do_noop_commit() {
    local author_name="$1" author_email="$2" message="$3" note="$4"
    local marker="chore-$(date +%s%N | tail -c 8)"
    do_commit "$author_name" "$author_email" "$message" "$note" \
        "chore/.${marker}" "# Marker file for chore commit — ignored
timestamp: $(date -u +%FT%TZ)
note: ${note}"
}

# do_branch <author_name> <author_email> <branch_name> <note>
do_branch() {
    local author_name="$1" author_email="$2" branch="$3" note="$4"
    wait_between
    header "🌿 Branch created by ${author_name}"
    echo -e "${YELLOW}  Branch:${RESET} ${branch}"
    if [ -n "$note" ]; then echo -e "${GREY}  ↳ ${note}${RESET}"; fi

    git checkout -b "$branch" --quiet 2>/dev/null || git checkout "$branch" --quiet
    git push -u origin "$branch" --quiet 2>&1 | grep -v "^To " || true
    git checkout main --quiet 2>/dev/null || git checkout master --quiet
    echo -e "${GREEN}  ✓ Branch pushed${RESET}"
}

# open_issue <title> <body> <note>
# Sets ISSUE_NUMBER global on success.
open_issue() {
    local title="$1" body="$2" note="$3"
    ISSUE_NUMBER=""
    if [ "$SKIP_ISSUES" = true ]; then
        echo -e "${GREY}  (skipped — issue events disabled)${RESET}"
        return
    fi

    wait_between
    header "🐛 Issue opened"
    echo -e "${YELLOW}  Title:${RESET} $title"
    if [ -n "$note" ]; then echo -e "${GREY}  ↳ ${note}${RESET}"; fi

    if [ "$HAS_GH" = true ]; then
        local url
        url=$(gh issue create --repo "$REPO_SLUG" --title "$title" --body "$body" 2>/dev/null || echo "")
        ISSUE_NUMBER=$(echo "$url" | grep -oE '[0-9]+$' || echo "")
    else
        local resp
        resp=$(curl -s -X POST \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${REPO_SLUG}/issues" \
            -d "$(printf '{"title":%s,"body":%s}' "$(jq -Rn --arg t "$title" '$t')" "$(jq -Rn --arg b "$body" '$b')")")
        ISSUE_NUMBER=$(echo "$resp" | grep -oE '"number":\s*[0-9]+' | head -n1 | grep -oE '[0-9]+')
    fi

    if [ -n "$ISSUE_NUMBER" ]; then
        echo -e "${GREEN}  ✓ Issue #${ISSUE_NUMBER} opened${RESET}"
        opened_issue_numbers+=("$ISSUE_NUMBER")
    else
        echo -e "${RED}  ✗ Failed to open issue${RESET}"
    fi
}

# comment_issue <issue_number> <body> <note>
comment_issue() {
    local num="$1" body="$2" note="$3"
    if [ "$SKIP_ISSUES" = true ] || [ -z "$num" ]; then return; fi

    wait_between
    header "💬 Comment on issue #${num}"
    if [ -n "$note" ]; then echo -e "${GREY}  ↳ ${note}${RESET}"; fi

    if [ "$HAS_GH" = true ]; then
        gh issue comment "$num" --repo "$REPO_SLUG" --body "$body" &>/dev/null || true
    else
        curl -s -X POST \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${REPO_SLUG}/issues/${num}/comments" \
            -d "$(printf '{"body":%s}' "$(jq -Rn --arg b "$body" '$b')")" >/dev/null
    fi
    echo -e "${GREEN}  ✓ Comment posted${RESET}"
}

# close_issue <issue_number> <note>
close_issue() {
    local num="$1" note="$2"
    if [ "$SKIP_ISSUES" = true ] || [ -z "$num" ]; then return; fi

    wait_between
    header "✅ Issue #${num} closed"
    if [ -n "$note" ]; then echo -e "${GREY}  ↳ ${note}${RESET}"; fi

    if [ "$HAS_GH" = true ]; then
        gh issue close "$num" --repo "$REPO_SLUG" &>/dev/null || true
    else
        curl -s -X PATCH \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${REPO_SLUG}/issues/${num}" \
            -d '{"state":"closed"}' >/dev/null
    fi
    echo -e "${GREEN}  ✓ Closed${RESET}"
}

# ── Banner ────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║         TeamFlow GitHub Sync — Long Simulation                ║${RESET}"
echo -e "${CYAN}║                                                               ║${RESET}"
echo -e "${CYAN}║  A realistic stream of team activity on the Acme repo:        ║${RESET}"
echo -e "${CYAN}║    • Commits from multiple authors                            ║${RESET}"
echo -e "${CYAN}║    • Issues opened (→ auto-create tasks on TeamFlow board)    ║${RESET}"
echo -e "${CYAN}║    • Comments, branches, and issue closes                     ║${RESET}"
echo -e "${CYAN}║    • ~70 events per loop at random 10-30s intervals           ║${RESET}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Repo:    ${CYAN}${REPO_SLUG}${RESET}"
echo -e "  Mode:    ${YELLOW}${MODE}${RESET}"
echo -e "  Loops:   ${YELLOW}${LOOPS}${RESET}"
echo -e "  Issues:  $([ "$SKIP_ISSUES" = true ] && echo -e "${RED}disabled${RESET}" || echo -e "${GREEN}enabled via $([ "$HAS_GH" = true ] && echo gh || echo curl)${RESET}")"
echo ""
read -p "  Press Enter to start the simulation..."

# ═══════════════════════════════════════════════════════════════════
#  THE SCRIPT
# ═══════════════════════════════════════════════════════════════════

run_simulation() {

# ──────────── PHASE 1: morning — people start the day ─────────────

do_noop_commit "Luca Ferraro" "luca@acme.dev" \
    "chore(lint): silence eslint unused-var warnings in legacy utils

Cleans up noise so CI output is readable again." \
    "noise commit — shouldn't match any subtask"

do_branch "Marcus Osei" "marcus@acme.dev" \
    "feature/payment-webhooks" \
    "branch for webhook work"

open_issue \
    "Dashboard loading spinner flashes on fast connections" \
    "On fast connections the skeleton loader briefly appears then disappears within 50ms, causing a visible flash. Should debounce or only show after 200ms delay.

Steps to reproduce:
1. Open dashboard on a fast connection
2. Observe flash of skeleton before real content loads

Expected: no flash, or delayed spinner." \
    "TeamFlow should auto-create a task for this"
ISSUE_DASHBOARD_FLASH=$ISSUE_NUMBER

# ── Subtask matches (same 8 as before, spread out) ────────────────

do_commit "Marcus Osei" "marcus@acme.dev" \
    "feat(webhooks): handle checkout.session.completed Stripe webhook event

Processes the checkout session completed event from Stripe,
creates subscription record and sends confirmation." \
    "matches st3-3" \
    "src/webhooks/checkout-completed.js" \
    'module.exports = async function handleCheckoutCompleted(event) {
  const session = event.data.object;
  await db.subscriptions.create({
    stripeCustomerId: session.customer,
    stripeSubscriptionId: session.subscription,
    status: "active",
    plan: session.metadata.plan,
    startedAt: new Date(),
  });
  await emailService.sendConfirmation(session.customer);
};'

comment_issue "$ISSUE_DASHBOARD_FLASH" \
    "Assigning this to myself. Will investigate today." \
    "comment on the dashboard issue"

do_commit "Sophie Andersen" "sophie@acme.dev" \
    "feat(dashboard): implement ActivityFeed component with infinite scroll

Adds the activity feed widget to the dashboard with
cursor-based infinite scroll loading." \
    "matches st4-3" \
    "src/components/ActivityFeed.jsx" \
    'import React, { useState, useEffect, useRef } from "react";
export function ActivityFeed() {
  const [items, setItems] = useState([]);
  const [cursor, setCursor] = useState(null);
  const sentinelRef = useRef(null);
  useEffect(() => {
    const obs = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting) loadMore();
    });
    if (sentinelRef.current) obs.observe(sentinelRef.current);
    return () => obs.disconnect();
  }, [cursor]);
  async function loadMore() {
    const res = await fetch(`/api/activity?cursor=${cursor || ""}`);
    const data = await res.json();
    setItems(prev => [...prev, ...data.items]);
    setCursor(data.nextCursor);
  }
  return <div>{items.map(i => <div key={i.id}>{i.text}</div>)}<div ref={sentinelRef} /></div>;
}'

open_issue \
    "Date picker breaks on Safari 16" \
    "The native date picker in the Settings → Preferences panel doesn't open on Safari 16. Works fine on Chrome and Firefox.

Might be related to the \`input[type=date]\` polyfill we dropped last month." \
    "another task will be created"
ISSUE_SAFARI_DATE=$ISSUE_NUMBER

do_noop_commit "Priya Nair" "priya@acme.dev" \
    "docs(readme): add developer onboarding section

Covers environment setup, database seeding, and running tests locally." \
    "doc update — shouldn't match"

# ──────────── PHASE 2: midday — heavy activity ────────────────────

do_commit "Marcus Osei" "marcus@acme.dev" \
    "feat(search): implement /api/search endpoint with full-text filter

Adds the search endpoint with pg_trgm full-text matching
and faceted filters for users and records." \
    "matches st5-3" \
    "src/routes/search.js" \
    'const router = require("express").Router();
router.get("/api/search", async (req, res) => {
  const { q, type, limit = 20 } = req.query;
  if (!q || q.length < 2) return res.status(400).json({ error: "Query too short" });
  const results = await db.query(`
    SELECT id, title, type, ts_rank(search_vector, plainto_tsquery($1)) AS rank
    FROM records WHERE search_vector @@ plainto_tsquery($1)
    AND ($2::text IS NULL OR type = $2) ORDER BY rank DESC LIMIT $3
  `, [q, type || null, limit]);
  res.json({ query: q, items: results.rows });
});
module.exports = router;'

do_branch "Sophie Andersen" "sophie@acme.dev" \
    "feature/dashboard-widgets" \
    "branch for widget grid redesign"

do_commit "Priya Nair" "priya@acme.dev" \
    "feat(onboarding): build email templates in MJML for drip campaign

Creates MJML templates for the 5-step onboarding email sequence:
welcome, getting started, features, tips, and feedback request." \
    "matches st6-3" \
    "src/emails/templates/welcome.mjml" \
    '<mjml>
  <mj-body>
    <mj-section background-color="#f4f4f7">
      <mj-column>
        <mj-text font-size="24px" font-weight="bold">Welcome to Acme!</mj-text>
        <mj-text>We are excited to have you on board.</mj-text>
        <mj-button href="https://acme.dev/start">Get Started</mj-button>
      </mj-column>
    </mj-section>
  </mj-body>
</mjml>'

comment_issue "$ISSUE_SAFARI_DATE" \
    "I think this is because we switched to the native picker. Might need to bring back the fallback component for Safari < 17." \
    ""

do_noop_commit "Luca Ferraro" "luca@acme.dev" \
    "style(tokens): nudge border-radius from 6px to 8px on all cards

Matches the updated Figma component library." \
    "design tweak"

do_commit "Marcus Osei" "marcus@acme.dev" \
    "feat(webhooks): handle invoice.payment_failed webhook with retry logic

Adds handler for failed Stripe invoice payments.
Implements exponential backoff retry and notifies the user." \
    "matches st3-4" \
    "src/webhooks/invoice-payment-failed.js" \
    'const MAX_RETRIES = 3;
const RETRY_DELAYS = [60000, 300000, 900000];
module.exports = async function handleInvoicePaymentFailed(event) {
  const invoice = event.data.object;
  const attempt = invoice.attempt_count || 1;
  if (attempt <= MAX_RETRIES) {
    await scheduler.schedule("retry_payment", {
      invoiceId: invoice.id, customerId: invoice.customer, attempt: attempt + 1,
    }, { delay: RETRY_DELAYS[attempt - 1] });
  } else {
    await db.subscriptions.update({ stripeCustomerId: invoice.customer }, { status: "past_due" });
    await emailService.sendPaymentFailedFinal(invoice.customer, invoice.id);
  }
};'

open_issue \
    "Add Datadog tracing to all outbound HTTP calls" \
    "We're flying blind on third-party service latency (Stripe, Resend, Slack). Need to instrument axios with dd-trace so we can see p95/p99 per external service.

Nice-to-have: break down by route so we can tell which endpoints are slow because of external calls." \
    "creates a new task — won't be auto-fixed"
ISSUE_DATADOG=$ISSUE_NUMBER

# ──────────── PHASE 3: afternoon — fixes and closes ───────────────

do_commit "Sophie Andersen" "sophie@acme.dev" \
    "feat(dashboard): wire up quick-action shortcuts with Cmd+K command palette

Adds keyboard shortcut handler and command palette overlay
for quick actions on the dashboard." \
    "matches st4-4" \
    "src/components/CommandPalette.jsx" \
    'import React, { useState, useEffect } from "react";
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
}'

do_commit "Sophie Andersen" "sophie@acme.dev" \
    "fix(dashboard): delay skeleton loader by 200ms to prevent flash

Fixes the brief flash of loading state on fast connections
by only showing the skeleton if the request takes longer than 200ms." \
    "fixes the dashboard-flash issue" \
    "src/hooks/useDelayedLoading.js" \
    'import { useState, useEffect } from "react";
export function useDelayedLoading(loading, delay = 200) {
  const [show, setShow] = useState(false);
  useEffect(() => {
    if (!loading) { setShow(false); return; }
    const t = setTimeout(() => setShow(true), delay);
    return () => clearTimeout(t);
  }, [loading, delay]);
  return show;
}'

close_issue "$ISSUE_DASHBOARD_FLASH" \
    "closed → TeamFlow should mark the linked task complete"

do_noop_commit "Marcus Osei" "marcus@acme.dev" \
    "refactor(db): rename internal query helpers for clarity

No functional change — renames \`qOne\` → \`queryOne\`, \`qMany\` → \`queryMany\`." \
    ""

do_commit "Marcus Osei" "marcus@acme.dev" \
    "feat(search): add cursor-based pagination to search filter API

Implements cursor-based pagination for the search endpoint
using encoded timestamps for stable page traversal." \
    "matches st5-4" \
    "src/lib/pagination.js" \
    'function encodeCursor(ts, id) { return Buffer.from(`${ts}:${id}`).toString("base64url"); }
function decodeCursor(c) {
  const [ts, id] = Buffer.from(c, "base64url").toString().split(":");
  return { ts, id };
}
async function paginatedSearch(query, cursor, limit = 20) {
  const params = [query];
  let where = "WHERE search_vector @@ plainto_tsquery($1)";
  if (cursor) {
    const { ts, id } = decodeCursor(cursor);
    params.push(ts, id);
    where += ` AND (created_at, id) < ($2, $3)`;
  }
  params.push(limit + 1);
  const { rows } = await db.query(`SELECT * FROM records ${where} ORDER BY created_at DESC, id DESC LIMIT $${params.length}`, params);
  const hasMore = rows.length > limit;
  return { items: hasMore ? rows.slice(0, -1) : rows, hasMore };
}
module.exports = { paginatedSearch };'

open_issue \
    "Rate limiting on /api/search" \
    "The search endpoint has no rate limiting. We should add per-user limits (20 req/min is probably fine) before we ship it to production. Redis token bucket would be ideal since we already have Redis." \
    ""
ISSUE_RATE_LIMIT=$ISSUE_NUMBER

do_noop_commit "Priya Nair" "priya@acme.dev" \
    "chore(deps): bump nodemailer from 6.9.7 to 6.9.14

Patch-level bump, no API changes." \
    "dep bump"

# ──────────── PHASE 4: evening — more work, more issues ───────────

do_commit "Priya Nair" "priya@acme.dev" \
    "feat(onboarding): wire Resend API to user-created event trigger

Connects the Resend email API to the user signup event
so the onboarding drip campaign starts automatically." \
    "matches st6-4" \
    "src/emails/onboarding.js" \
    'const { Resend } = require("resend");
const resend = new Resend(process.env.RESEND_API_KEY);
const DRIP = [
  { delay: 0, template: "welcome", subject: "Welcome!" },
  { delay: 86400000, template: "getting-started", subject: "Getting started" },
  { delay: 604800000, template: "tips", subject: "Pro tips" },
];
async function onUserCreated(user) {
  for (const step of DRIP) {
    await scheduler.schedule("send_onboarding_email", {
      userId: user.id, email: user.email, template: step.template, subject: step.subject,
    }, { delay: step.delay });
  }
}
module.exports = { onUserCreated };'

comment_issue "$ISSUE_RATE_LIMIT" \
    "+1 — we saw someone scraping search results last week. This is not just nice-to-have." \
    ""

do_branch "Luca Ferraro" "luca@acme.dev" \
    "design/a11y-settings-page" \
    ""

do_noop_commit "Sophie Andersen" "sophie@acme.dev" \
    "test(dashboard): add snapshot tests for WidgetGrid component" \
    ""

open_issue \
    "CSV export truncates emoji in user names" \
    "The GDPR data export CSV shows \`?\` instead of emoji in user display names. Probably a UTF-8 BOM issue on the export stream." \
    ""
ISSUE_CSV_EMOJI=$ISSUE_NUMBER

do_noop_commit "Marcus Osei" "marcus@acme.dev" \
    "perf(db): add composite index on (user_id, created_at) for activity queries

Cuts the p95 of /api/activity from 280ms to 45ms based on staging metrics." \
    ""

comment_issue "$ISSUE_DATADOG" \
    "Bumping priority on this — we had a 3-minute Stripe outage yesterday and we only found out from their status page, not our own metrics." \
    ""

# ──────────── PHASE 5: next day — catchup ─────────────────────────

do_commit "Luca Ferraro" "luca@acme.dev" \
    "a11y(settings): add ARIA labels to all form inputs on settings page

Covers the Preferences, Notifications, and Security sub-panels.
Addresses axe-core warnings for unlabelled inputs." \
    "might match st10-2" \
    "src/pages/settings/Preferences.jsx" \
    'export function PreferencesPanel() {
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
}'

do_noop_commit "NOVA-3" "nova3@acme.dev" \
    "chore(bot): auto-format with prettier after dependency bumps

Automated by NOVA-3." \
    "bot commit from the AI agent"

do_commit "Marcus Osei" "marcus@acme.dev" \
    "fix(webhooks): add Stripe webhook signature verification

Verifies the stripe-signature header on every webhook request
using the endpoint secret. Rejects requests with invalid signatures." \
    "" \
    "src/middleware/verify-stripe-webhook.js" \
    'const stripe = require("stripe")(process.env.STRIPE_SECRET);
const WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET;
module.exports = function verifyStripeWebhook(req, res, next) {
  const sig = req.headers["stripe-signature"];
  try {
    req.stripeEvent = stripe.webhooks.constructEvent(req.rawBody, sig, WEBHOOK_SECRET);
    next();
  } catch (err) {
    console.error("Invalid Stripe signature", err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }
};'

close_issue "$ISSUE_SAFARI_DATE" \
    ""

do_noop_commit "Priya Nair" "priya@acme.dev" \
    "docs(emails): document which events trigger each drip email

Adds a table to docs/emails.md mapping app events to email templates." \
    ""

do_branch "Marcus Osei" "marcus@acme.dev" \
    "feature/rate-limiting" \
    ""

do_commit "Marcus Osei" "marcus@acme.dev" \
    "feat(search): add per-user rate limiting with Redis token bucket

20 requests per minute per authenticated user on /api/search.
Returns 429 with Retry-After header when exceeded." \
    "fixes the rate-limit issue" \
    "src/middleware/rate-limit.js" \
    'const redis = require("./redis");
module.exports = function rateLimit({ key, limit, windowMs }) {
  return async (req, res, next) => {
    const k = `rl:${key}:${req.user.id}`;
    const count = await redis.incr(k);
    if (count === 1) await redis.pexpire(k, windowMs);
    if (count > limit) {
      const ttl = await redis.pttl(k);
      res.set("Retry-After", Math.ceil(ttl / 1000));
      return res.status(429).json({ error: "Too many requests" });
    }
    next();
  };
};'

close_issue "$ISSUE_RATE_LIMIT" \
    ""

do_noop_commit "Luca Ferraro" "luca@acme.dev" \
    "style(login): align social login buttons to match email/password layout" \
    ""

do_commit "Sophie Andersen" "sophie@acme.dev" \
    "fix(csv-export): write UTF-8 BOM header so Excel opens files correctly

Prepends \\ufeff to CSV exports so multi-byte characters (emoji,
non-Latin names) render correctly when opened in Excel." \
    "fixes the CSV emoji issue" \
    "src/lib/csv-export.js" \
    'const BOM = "\ufeff";
function writeCSV(stream, rows) {
  stream.write(BOM);
  for (const row of rows) {
    stream.write(row.map(escapeCell).join(",") + "\n");
  }
}
function escapeCell(v) {
  const s = String(v ?? "");
  return /[,"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
module.exports = { writeCSV };'

close_issue "$ISSUE_CSV_EMOJI" \
    ""

# ──────────── PHASE 6: background hum — more variety ──────────────

open_issue \
    "Flaky test: auth.integration.test.js times out in CI" \
    "The Google OAuth integration test times out roughly 1 in 20 runs in CI, passes locally every time. Might be a race condition in the mocked provider setup." \
    ""
ISSUE_FLAKY=$ISSUE_NUMBER

do_noop_commit "NOVA-3" "nova3@acme.dev" \
    "chore(deps): weekly dependabot-style bump of patch-level deps" \
    ""

do_noop_commit "Sophie Andersen" "sophie@acme.dev" \
    "refactor(dashboard): extract useWidgetLayout hook from DashboardGrid" \
    ""

do_commit "Priya Nair" "priya@acme.dev" \
    "feat(emails): add unsubscribe footer to all marketing templates

Required for CAN-SPAM compliance. Adds a one-click unsubscribe
token link to the footer of every drip email." \
    "" \
    "src/emails/partials/footer.mjml" \
    '<mj-wrapper padding="16px 24px" background-color="#f8f9fb">
  <mj-section>
    <mj-column>
      <mj-text font-size="11px" color="#8a94a8" align="center">
        You are receiving this because you signed up for Acme.
        <a href="{{unsubscribeUrl}}">Unsubscribe</a> from these emails.
      </mj-text>
    </mj-column>
  </mj-section>
</mj-wrapper>'

comment_issue "$ISSUE_FLAKY" \
    "I'll take a look. Probably need to add a fake clock to the OAuth mock." \
    ""

do_noop_commit "Luca Ferraro" "luca@acme.dev" \
    "docs(design): add light/dark mode contrast ratio matrix to README" \
    ""

do_commit "Marcus Osei" "marcus@acme.dev" \
    "fix(auth): use fake timers in OAuth integration test to prevent flake

Replaces real \`setTimeout\` with sinon fake timers in the mock
OAuth provider, eliminating the race condition on slow CI runners." \
    "fixes the flaky test issue" \
    "src/auth/oauth.test.js" \
    'const sinon = require("sinon");
describe("OAuth flow", () => {
  let clock;
  beforeEach(() => { clock = sinon.useFakeTimers(); });
  afterEach(() => { clock.restore(); });
  it("handles Google callback", async () => {
    const result = await mockProvider.callback("fake-code");
    clock.tick(5000);
    expect(result.accessToken).to.exist;
  });
});'

close_issue "$ISSUE_FLAKY" \
    ""

do_noop_commit "NOVA-3" "nova3@acme.dev" \
    "chore(bot): run monthly license audit — no new violations" \
    ""

open_issue \
    "Password reset link doesn't expire" \
    "Our password reset tokens never expire based on manual testing. They should expire after 1 hour." \
    "security issue"

open_issue \
    "Dashboard time filter uses wrong timezone" \
    "The 'Last 7 days' filter uses UTC instead of the user's local timezone, so Pacific users see 7 days that start mid-afternoon." \
    ""

do_noop_commit "Sophie Andersen" "sophie@acme.dev" \
    "style(settings): switch from grid to flex on the mobile settings page" \
    ""

do_commit "Luca Ferraro" "luca@acme.dev" \
    "a11y(settings): verify keyboard-only navigation works across all tabs

Tab order, focus outlines, and escape-to-close now work consistently
on Preferences, Notifications, Security, and Billing sub-panels." \
    "" \
    "src/pages/settings/KeyboardNav.js" \
    'export function installKeyboardNav(container) {
  const focusable = container.querySelectorAll("button, [href], input, select, textarea, [tabindex]:not([tabindex=\\"-1\\"])");
  container.addEventListener("keydown", (e) => {
    if (e.key === "Tab") return;
    if (e.key === "Escape") container.dispatchEvent(new CustomEvent("close"));
  });
  return focusable;
}'

do_noop_commit "Marcus Osei" "marcus@acme.dev" \
    "perf(api): cache frequently-accessed /api/me responses in Redis for 30s" \
    ""

do_noop_commit "Priya Nair" "priya@acme.dev" \
    "docs(ops): add runbook for handling Resend API outages" \
    ""

do_branch "Sophie Andersen" "sophie@acme.dev" \
    "fix/timezone-filter" \
    ""

do_commit "Marcus Osei" "marcus@acme.dev" \
    "fix(auth): password reset tokens now expire after 1 hour

Adds \`expires_at\` to the password_reset_tokens table and rejects
expired tokens with a clear error message." \
    "fixes the password-reset security issue" \
    "src/auth/password-reset.js" \
    'const TOKEN_TTL_MS = 60 * 60 * 1000;
async function createResetToken(userId) {
  const token = crypto.randomBytes(32).toString("hex");
  await db.query(
    "INSERT INTO password_reset_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)",
    [userId, token, new Date(Date.now() + TOKEN_TTL_MS)],
  );
  return token;
}
async function consumeResetToken(token) {
  const { rows } = await db.query(
    "SELECT user_id FROM password_reset_tokens WHERE token = $1 AND expires_at > NOW()",
    [token],
  );
  if (!rows.length) throw new Error("Token is invalid or expired");
  await db.query("DELETE FROM password_reset_tokens WHERE token = $1", [token]);
  return rows[0].user_id;
}
module.exports = { createResetToken, consumeResetToken };'

do_noop_commit "Luca Ferraro" "luca@acme.dev" \
    "style(buttons): switch primary button gradient to solid fill

The gradient read as noise on mobile screens. Solid fill is cleaner." \
    ""

do_commit "Sophie Andersen" "sophie@acme.dev" \
    "fix(dashboard): respect user timezone for 'Last 7 days' filter

Uses the browser's Intl.DateTimeFormat().resolvedOptions().timeZone
instead of defaulting to UTC." \
    "fixes the timezone-filter issue" \
    "src/lib/date-ranges.js" \
    'function getUserTimezone() {
  try { return Intl.DateTimeFormat().resolvedOptions().timeZone; }
  catch { return "UTC"; }
}
function last7Days() {
  const tz = getUserTimezone();
  const now = new Date();
  const end = new Date(now.toLocaleString("en-US", { timeZone: tz }));
  const start = new Date(end);
  start.setDate(start.getDate() - 7);
  return { start, end, timezone: tz };
}
module.exports = { last7Days, getUserTimezone };'

comment_issue "$ISSUE_DATADOG" \
    "Starting on this tomorrow. Will add dd-trace to the axios instance in our shared HTTP client first, then rollout." \
    ""

do_noop_commit "Marcus Osei" "marcus@acme.dev" \
    "chore(ci): cache npm deps in GitHub Actions to speed up builds

Drops average CI time from 6m to 2m30s." \
    ""

do_noop_commit "NOVA-3" "nova3@acme.dev" \
    "chore(bot): rotate API keys in .env.example to avoid confusion

Replaces expired example keys with clearly-fake placeholders." \
    ""

do_commit "Priya Nair" "priya@acme.dev" \
    "feat(emails): add preview text support to MJML templates

Each template now sets a preview-text attribute that shows up
in inbox previews on Gmail, Outlook, and Apple Mail." \
    "" \
    "src/emails/partials/preview.mjml" \
    '<mj-raw>
  <!--[if !mso]><!-->
  <div style="display:none;max-height:0;overflow:hidden;">
    {{previewText}}
  </div>
  <!--<![endif]-->
</mj-raw>'

open_issue \
    "Drag-and-drop task reordering is janky on Firefox" \
    "When you drag a task card on the kanban, Firefox shows a ghost image that doesn't follow the cursor until you move ~50px. Smooth on Chrome." \
    ""

do_noop_commit "Sophie Andersen" "sophie@acme.dev" \
    "test(components): add visual regression tests via Chromatic for 14 components" \
    ""

do_noop_commit "Luca Ferraro" "luca@acme.dev" \
    "docs(a11y): add WCAG 2.2 AA checklist to contributor guide" \
    ""

do_noop_commit "Marcus Osei" "marcus@acme.dev" \
    "refactor(webhooks): centralise retry logic into a shared queue consumer

No behaviour change — extracts duplicated retry code from 3 webhook handlers." \
    ""

# ──────────── End of simulation ───────────────────────────────────
}

# ── Run loops ─────────────────────────────────────────────────────
for i in $(seq 1 "$LOOPS"); do
    echo ""
    echo -e "${PURPLE}════════════════════════════════════════════════════════════${RESET}"
    echo -e "${PURPLE}  LOOP ${i}/${LOOPS}${RESET}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════${RESET}"
    run_simulation
done

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  ✅ Simulation complete — ${event_count} events fired.${RESET}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  TeamFlow polls every 60 seconds, so the last few events"
echo -e "  may take a minute to appear on the board."
echo ""
echo -e "  Open ${CYAN}http://localhost:3001${RESET} to watch the board update."
echo ""
