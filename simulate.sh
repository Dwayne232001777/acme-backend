#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  simulate.sh — Simulates a team working on the Acme Backend repo
#
#  Each commit message is crafted to keyword-match a specific
#  incomplete subtask on the TeamFlow board (from init.sql seed data).
#
#  Usage:
#    ./simulate.sh              # run all commits with 45s delay
#    ./simulate.sh --fast       # 10s delay (quick demo)
#    ./simulate.sh --instant    # no delay (push all at once)
#    ./simulate.sh --step       # wait for Enter between each commit
# ─────────────────────────────────────────────────────────────────

set -e

DELAY=45  # seconds between commits (default)
STEP_MODE=false

case "${1:-}" in
    --fast)    DELAY=10 ;;
    --instant) DELAY=0  ;;
    --step)    STEP_MODE=true ;;
esac

# ── Colours ────────────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREY='\033[0;90m'
RESET='\033[0m'

# ── Helper ─────────────────────────────────────────────────────────
commit_count=0
total_commits=8

do_commit() {
    local author_name="$1"
    local author_email="$2"
    local message="$3"
    local target_subtask="$4"
    local file_content="$5"
    local file_path="$6"

    commit_count=$((commit_count + 1))

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  Commit ${commit_count}/${total_commits}${RESET}"
    echo -e "${YELLOW}  Author:  ${author_name}${RESET}"
    echo -e "  Message: ${message}"
    echo -e "${GREY}  Target:  ${target_subtask}${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${RESET}"

    # Write file change
    mkdir -p "$(dirname "$file_path")"
    echo "$file_content" > "$file_path"

    git add -A
    git commit \
        --author="${author_name} <${author_email}>" \
        -m "$message" \
        --quiet

    git push --quiet

    echo -e "${GREEN}  ✓ Pushed to GitHub${RESET}"
    echo -e "${GREY}  → TeamFlow will pick this up within 60 seconds${RESET}"

    if [ "$STEP_MODE" = true ]; then
        echo ""
        read -p "  Press Enter for next commit..."
    elif [ "$DELAY" -gt 0 ] && [ "$commit_count" -lt "$total_commits" ]; then
        echo -e "${GREY}  Waiting ${DELAY}s before next commit...${RESET}"
        sleep "$DELAY"
    fi
}

# ── Pre-flight checks ─────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Run this script from inside the git repo."
    exit 1
fi

if ! git remote get-url origin &>/dev/null; then
    echo "ERROR: No 'origin' remote configured. Push to GitHub first."
    exit 1
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║  TeamFlow GitHub Sync — Live Simulation                  ║${RESET}"
echo -e "${CYAN}║                                                         ║${RESET}"
echo -e "${CYAN}║  This script creates ${total_commits} commits as different team members.  ║${RESET}"
echo -e "${CYAN}║  Each commit matches a subtask on the TeamFlow board.    ║${RESET}"
echo -e "${CYAN}║                                                         ║${RESET}"
echo -e "${CYAN}║  Make sure TeamFlow is running: docker-compose up        ║${RESET}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""

if [ "$STEP_MODE" = true ]; then
    echo -e "${YELLOW}  Mode: STEP (press Enter between commits)${RESET}"
elif [ "$DELAY" -eq 0 ]; then
    echo -e "${YELLOW}  Mode: INSTANT (all commits at once)${RESET}"
else
    echo -e "${YELLOW}  Mode: ${DELAY}s delay between commits${RESET}"
fi

read -p "  Press Enter to start the simulation..."

# ═══════════════════════════════════════════════════════════════════
#  COMMITS — each targets a specific incomplete subtask
#
#  The keyword matcher needs overlap between:
#    1. Task title/description keywords (>4 chars)
#    2. Subtask text keywords (>4 chars)
#    3. Commit message text
# ═══════════════════════════════════════════════════════════════════

# ── Commit 1: Marcus Osei — Payment Webhook (st3-3) ──────────────
# Task: "Payment Webhook Handler" / "Process Stripe events..."
# Subtask: "Handle checkout.session.completed event"
do_commit \
    "Marcus Osei" \
    "marcus@acme.dev" \
    "feat(webhooks): handle checkout.session.completed Stripe webhook event

Processes the checkout session completed event from Stripe,
creates subscription record and sends confirmation." \
    "st3-3: Handle checkout.session.completed event" \
    'module.exports = async function handleCheckoutCompleted(event) {
  const session = event.data.object;
  const customerId = session.customer;
  const subscriptionId = session.subscription;

  await db.subscriptions.create({
    stripeCustomerId: customerId,
    stripeSubscriptionId: subscriptionId,
    status: "active",
    plan: session.metadata.plan,
    startedAt: new Date(),
  });

  await emailService.sendConfirmation(customerId);
  console.log(`Checkout completed for customer ${customerId}`);
};' \
    "src/webhooks/checkout-completed.js"

# ── Commit 2: Sophie Andersen — Dashboard (st4-3) ────────────────
# Task: "User Dashboard v2" / "Rebuild the home dashboard with a widget grid, activity feed..."
# Subtask: "Implement ActivityFeed with infinite scroll"
do_commit \
    "Sophie Andersen" \
    "sophie@acme.dev" \
    "feat(dashboard): implement ActivityFeed component with infinite scroll

Adds the activity feed widget to the dashboard with
cursor-based infinite scroll loading." \
    "st4-3: Implement ActivityFeed with infinite scroll" \
    'import React, { useState, useEffect, useRef } from "react";

export function ActivityFeed() {
  const [items, setItems] = useState([]);
  const [cursor, setCursor] = useState(null);
  const [loading, setLoading] = useState(false);
  const sentinelRef = useRef(null);

  useEffect(() => {
    const observer = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting && !loading) loadMore();
    });
    if (sentinelRef.current) observer.observe(sentinelRef.current);
    return () => observer.disconnect();
  }, [cursor, loading]);

  async function loadMore() {
    setLoading(true);
    const res = await fetch(`/api/activity?cursor=${cursor || ""}`);
    const data = await res.json();
    setItems(prev => [...prev, ...data.items]);
    setCursor(data.nextCursor);
    setLoading(false);
  }

  return (
    <div className="activity-feed">
      {items.map(item => (
        <div key={item.id} className="feed-item">{item.text}</div>
      ))}
      <div ref={sentinelRef} />
      {loading && <div className="spinner" />}
    </div>
  );
}' \
    "src/components/ActivityFeed.jsx"

# ── Commit 3: Marcus Osei — Search API (st5-3) ───────────────────
# Task: "Search & Filter API" / "Full-text search endpoint with faceted filters..."
# Subtask: "Implement /api/search endpoint"
do_commit \
    "Marcus Osei" \
    "marcus@acme.dev" \
    "feat(search): implement /api/search endpoint with full-text filter

Adds the search endpoint with pg_trgm full-text matching
and faceted filters for users and records." \
    "st5-3: Implement /api/search endpoint" \
    'const express = require("express");
const router = express.Router();

router.get("/api/search", async (req, res) => {
  const { q, type, status, limit = 20, cursor } = req.query;

  if (!q || q.trim().length < 2) {
    return res.status(400).json({ error: "Query must be at least 2 characters" });
  }

  const results = await db.query(`
    SELECT id, title, type, status,
           ts_rank(search_vector, plainto_tsquery($1)) AS rank
    FROM records
    WHERE search_vector @@ plainto_tsquery($1)
      AND ($2::text IS NULL OR type = $2)
      AND ($3::text IS NULL OR status = $3)
    ORDER BY rank DESC
    LIMIT $4
  `, [q, type || null, status || null, limit]);

  res.json({
    query: q,
    count: results.rows.length,
    items: results.rows,
  });
});

module.exports = router;' \
    "src/routes/search.js"

# ── Commit 4: Priya Nair — Email templates (st6-3) ───────────────
# Task: "Onboarding Email Sequence" / "Five-step drip campaign... built with Resend and MJML."
# Subtask: "Build email templates in MJML"
do_commit \
    "Priya Nair" \
    "priya@acme.dev" \
    "feat(onboarding): build email templates in MJML for drip campaign

Creates MJML templates for the 5-step onboarding email sequence:
welcome, getting started, features, tips, and feedback request." \
    "st6-3: Build email templates in MJML" \
    '<mjml>
  <mj-body>
    <mj-section background-color="#f4f4f7">
      <mj-column>
        <mj-image width="120px" src="https://acme.dev/logo.png" />
        <mj-text font-size="24px" font-weight="bold" color="#1a1a2e">
          Welcome to Acme!
        </mj-text>
        <mj-text font-size="16px" color="#4a4a68" line-height="1.6">
          We are excited to have you on board. Here is what you can
          do to get started with your new account.
        </mj-text>
        <mj-button background-color="#5b8dee" color="white" href="https://acme.dev/start">
          Get Started
        </mj-button>
      </mj-column>
    </mj-section>
  </mj-body>
</mjml>' \
    "src/emails/templates/welcome.mjml"

# ── Commit 5: Marcus Osei — Payment webhook retry (st3-4) ────────
# Task: "Payment Webhook Handler" / "Process Stripe events..."
# Subtask: "Handle invoice.payment_failed with retry logic"
do_commit \
    "Marcus Osei" \
    "marcus@acme.dev" \
    "feat(webhooks): handle invoice.payment_failed webhook with retry logic

Adds handler for failed Stripe invoice payments.
Implements exponential backoff retry and notifies the user." \
    "st3-4: Handle invoice.payment_failed with retry logic" \
    'const MAX_RETRIES = 3;
const RETRY_DELAYS = [60_000, 300_000, 900_000]; // 1m, 5m, 15m

module.exports = async function handleInvoicePaymentFailed(event) {
  const invoice = event.data.object;
  const customerId = invoice.customer;
  const attemptCount = invoice.attempt_count || 1;

  console.log(`Payment failed for invoice ${invoice.id} (attempt ${attemptCount})`);

  if (attemptCount <= MAX_RETRIES) {
    const delay = RETRY_DELAYS[attemptCount - 1] || RETRY_DELAYS[RETRY_DELAYS.length - 1];
    await scheduler.schedule("retry_payment", {
      invoiceId: invoice.id,
      customerId,
      attempt: attemptCount + 1,
    }, { delay });
    console.log(`Scheduled retry in ${delay / 1000}s`);
  } else {
    await db.subscriptions.update(
      { stripeCustomerId: customerId },
      { status: "past_due" }
    );
    await emailService.sendPaymentFailedFinal(customerId, invoice.id);
    console.log(`Max retries reached — marked subscription as past_due`);
  }
};' \
    "src/webhooks/invoice-payment-failed.js"

# ── Commit 6: Sophie Andersen — Quick actions (st4-4) ─────────────
# Task: "User Dashboard v2" / "Rebuild the home dashboard with... quick actions."
# Subtask: "Wire up quick-action shortcuts (Cmd+K)"
do_commit \
    "Sophie Andersen" \
    "sophie@acme.dev" \
    "feat(dashboard): wire up quick-action shortcuts with Cmd+K command palette

Adds keyboard shortcut handler and command palette overlay
for quick actions on the dashboard." \
    "st4-4: Wire up quick-action shortcuts (Cmd+K)" \
    'import React, { useState, useEffect } from "react";

const ACTIONS = [
  { id: "new-task",     label: "Create new task",     icon: "+" },
  { id: "search",       label: "Search everything",   icon: "🔍" },
  { id: "settings",     label: "Open settings",       icon: "⚙" },
  { id: "team",         label: "View team members",   icon: "👥" },
  { id: "notifications",label: "Notifications",       icon: "🔔" },
];

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  useEffect(() => {
    function onKeyDown(e) {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setOpen(prev => !prev);
        setQuery("");
      }
      if (e.key === "Escape") setOpen(false);
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const filtered = ACTIONS.filter(a =>
    a.label.toLowerCase().includes(query.toLowerCase())
  );

  if (!open) return null;
  return (
    <div className="command-palette-overlay" onClick={() => setOpen(false)}>
      <div className="command-palette" onClick={e => e.stopPropagation()}>
        <input value={query} onChange={e => setQuery(e.target.value)}
               placeholder="Type a command..." autoFocus />
        {filtered.map(a => (
          <div key={a.id} className="command-item">
            <span>{a.icon}</span> {a.label}
          </div>
        ))}
      </div>
    </div>
  );
}' \
    "src/components/CommandPalette.jsx"

# ── Commit 7: Marcus Osei — Search pagination (st5-4) ────────────
# Task: "Search & Filter API" / "Full-text search endpoint with faceted filters..."
# Subtask: "Add cursor-based pagination"
do_commit \
    "Marcus Osei" \
    "marcus@acme.dev" \
    "feat(search): add cursor-based pagination to search filter API

Implements cursor-based pagination for the search endpoint
using encoded timestamps for stable page traversal." \
    "st5-4: Add cursor-based pagination" \
    'function encodeCursor(timestamp, id) {
  return Buffer.from(`${timestamp}:${id}`).toString("base64url");
}

function decodeCursor(cursor) {
  const decoded = Buffer.from(cursor, "base64url").toString();
  const [timestamp, id] = decoded.split(":");
  return { timestamp, id };
}

async function paginatedSearch(query, cursor, limit = 20) {
  let whereClause = "WHERE search_vector @@ plainto_tsquery($1)";
  const params = [query];

  if (cursor) {
    const { timestamp, id } = decodeCursor(cursor);
    params.push(timestamp, id);
    whereClause += ` AND (created_at, id) < ($${params.length - 1}, $${params.length})`;
  }

  params.push(limit + 1);
  const { rows } = await db.query(
    `SELECT * FROM records ${whereClause} ORDER BY created_at DESC, id DESC LIMIT $${params.length}`,
    params
  );

  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, -1) : rows;
  const nextCursor = hasMore
    ? encodeCursor(items[items.length - 1].created_at, items[items.length - 1].id)
    : null;

  return { items, nextCursor, hasMore };
}

module.exports = { paginatedSearch, encodeCursor, decodeCursor };' \
    "src/lib/pagination.js"

# ── Commit 8: Priya Nair — Wire Resend API (st6-4) ───────────────
# Task: "Onboarding Email Sequence" / "Five-step drip campaign... built with Resend and MJML."
# Subtask: "Wire Resend API to user-created event"
do_commit \
    "Priya Nair" \
    "priya@acme.dev" \
    "feat(onboarding): wire Resend API to user-created event trigger

Connects the Resend email API to the user signup event
so the onboarding drip campaign starts automatically." \
    "st6-4: Wire Resend API to user-created event" \
    'const { Resend } = require("resend");
const resend = new Resend(process.env.RESEND_API_KEY);

const DRIP_SCHEDULE = [
  { delay: 0,         template: "welcome",         subject: "Welcome to Acme!" },
  { delay: 86400000,  template: "getting-started",  subject: "Getting started with Acme" },
  { delay: 259200000, template: "features",         subject: "3 features you should try" },
  { delay: 604800000, template: "tips",             subject: "Pro tips from the team" },
  { delay: 1209600000,template: "feedback",         subject: "How is it going?" },
];

async function onUserCreated(user) {
  for (const step of DRIP_SCHEDULE) {
    await scheduler.schedule("send_onboarding_email", {
      userId: user.id,
      email: user.email,
      template: step.template,
      subject: step.subject,
    }, { delay: step.delay });
  }
  console.log(`Onboarding drip scheduled for ${user.email} (${DRIP_SCHEDULE.length} emails)`);
}

async function sendOnboardingEmail({ email, template, subject }) {
  const html = await renderMjmlTemplate(template);
  await resend.emails.send({
    from: "Acme <hello@acme.dev>",
    to: email,
    subject,
    html,
  });
}

module.exports = { onUserCreated, sendOnboardingEmail };' \
    "src/emails/onboarding.js"

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  ✅ Simulation complete! ${total_commits} commits pushed.${RESET}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  TeamFlow polls every 60 seconds, so all subtasks should"
echo -e "  be checked off within a minute or two."
echo ""
echo -e "  Open ${CYAN}http://localhost:3001${RESET} to watch the board update."
echo ""
