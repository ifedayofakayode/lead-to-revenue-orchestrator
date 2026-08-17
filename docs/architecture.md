# Architecture

The entire system runs as a single n8n workflow, with four independent trigger
points feeding into shared logic. This document maps every node to the phase
it belongs to, since the exported JSON itself doesn't expose that structure —
use it alongside `workflow-screenshot.png` to navigate the real canvas.

## Trigger 1: Lead Intake (primary flow)

**Ingestion & duplicate protection**
- `Webhook - Intake Form` — receives lead submissions (form/SMS/etc.)
- `Build Idempotency Key` — fingerprints the event from phone + message
- `Check Idempotency Key` — looks up the fingerprint in `idempotency_keys`
- `IF - Is New Event` → true: `Insert Idempotency Key` / false: `Update Duplicate Count`

**AI extraction**
- `Determine Timezone` — maps extracted state to an IANA timezone
- `Extract Lead Data` — calls OpenAI (JSON mode) to structure the raw message
- `Parse Extracted Data` — parses the AI's JSON response into usable fields
- `Insert Lead` — writes the structured record to `leads`
- `Log SMS Consent` — logs the intake-form consent decision to `consent_logs`

**Pricing & human-in-the-loop routing**
- `Lookup Pricing Rule` — date-aware price lookup against `pricing_rules`
- `IF - Pricing Not Found` → true: `Log Pricing Not Found`, `Queue Pricing Exception`
- `IF - Needs Human Approval` (OR: emergency / high price / low AI confidence)
  - true: `Send Approval Request` (Slack Send-and-Wait) → `IF - Was Approved`
    - true: `Update Lead - Quoted`, `Log Approval Event`
    - false: `Update Lead - Disqualified`, `Log Decline Event`
  - false: `Update Lead - Auto Quoted`, `Log Auto Quote Event`

**CRM sync & scheduling** (both approval paths merge here)
- `Sync Contact to HubSpot`
- `Create Deal`
- `Log HubSpot Sync`
- `Build Booking Link` — personalized Calendly URL
- `Log Booking Link`

**Consent-gated follow-up**
- `IF - Has SMS Consent`
  - true: `Build SMS Message` → `Simulate Send SMS` → `Wait Before Reminder` →
    `Recheck Lead Status` → `IF - Still Quoted`
    - true: `Build Reminder Message`, `Simulate Send Reminder`
    - false: `Log Reminder Skipped`
  - false: `Log SMS Skipped`

## Trigger 2: Booking Confirmation

Stands in for Calendly's real webhook (requires a paid plan) — swap the
trigger source only, no downstream changes needed once upgraded.

- `Webhook - Calendly Booking`
- `Find Lead By Email`
- `IF - Lead Found`
  - true: `Update Lead - Booked`, `Log Booking Confirmed`
  - false: `Notify Unmatched Booking`, `Queue Unmatched Booking Exception`

## Trigger 3: SMS Reply

Stands in for Twilio's real inbound-message webhook — same field names
(`From`, `Body`) Twilio actually sends, so swapping is a one-node change.

- `Webhook - SMS Reply`
- `Find Lead By Phone`
- `IF - Lead Found`
  - true: `Update Lead - Replied`, `Log Customer Reply`
  - false: `Notify Unmatched Reply`, `Queue Unmatched Reply Exception`

## Trigger 4: Exception Monitoring

Runs on a timer, independent of any customer action.

- `Schedule - Exception Check`
- `Check Aging Exceptions` — queries `exception_queue` for anything open past a threshold
- `IF - Has Aging Exceptions`
  - true: `Build Alert Summary` → `Alert - Aging Exceptions` (Slack)
  - false: no action (deliberate — a clean check isn't a loggable event)

## Design principles applied throughout

- **Fail loud, never silent** — every branch either advances the lead or logs
  why it didn't (`lead_events`, `exception_queue`); nothing dead-ends quietly.
- **Re-check live state after any wait** — `Recheck Lead Status` always
  queries fresh data post-`Wait`, never trusting what was known before the pause.
- **Swappable I/O boundaries** — simulated SMS and stand-in webhooks isolate
  "decide what to do" logic from "which vendor executes it," so real
  providers can be connected later with no logic changes.
- **State vs. history are separate concerns** — `leads.lead_status` always
  reflects current state; `lead_events` is the append-only record of how it
  got there. Both are needed; neither substitutes for the other.