# Lead-to-Revenue Orchestrator

An end-to-end, production-grade automation system that takes a lead from first contact to a booked, priced, CRM-synced opportunity. This is done with no manual data entry and no dropped leads. It is built for high-ticket home service businesses (HVAC, roofing, and similar trades).

## Overview

This project automates lead handling for HVAC/roofing-style service businesses through the following steps: 
- **Ingests leads** — captures leads from a web form
- **Extracts structured data from unstructured text** using OpenAI API (urgency, service type, budget signals, property details) via JSON-mode prompting
- **Scores and routes leads deterministically** — emergency jobs trigger immediate Slack alerts; low-priority leads enter automated nurture sequences
- **Generates dynamic preliminary pricing** from a rules-based pricing engine, with a stale-price guardrail that blocks quotes if pricing data hasn't been verified recently
- **Checks calendar availability and books appointments** with correct timezone handling between business and customer locations
- **Syncs to CRM (HubSpot)** as a downstream projection of a Postgres source of truth and not the other way around, so CRM downtime never blocks a customer response
- **Routes high-value quotes through human-in-the-loop approval** via interactive Slack buttons before anything reaches the customer
- **Runs compliant automated follow-up** with exact-match STOP/opt-out detection (TCPA-aware) and per-channel consent tracking
- **Tracks its own performance** — speed to first response, cost per lead, routing accuracy — via a Metabase dashboard built on the same event log

## Architecture

\`\`\`mermaid
flowchart TD
    A[Webhook: Intake Form] --> B[Duplicate Check - Idempotency]
    B --> C[OpenAI: Extract Lead Data]
    C --> D[Pricing Lookup]
    D --> E{Needs Human Approval?}
    E -->|Yes| F[Slack: Send and Wait for Approval]
    E -->|No| G[Auto-Quote]
    F --> H[HubSpot: Sync Contact and Deal]
    G --> H
    H --> I[Generate Calendly Booking Link]
    I --> J{SMS Consent Granted?}
    J -->|Yes| K[Simulated SMS + Reminder Loop]
    J -->|No| L[Log Skipped]
\`\`\`

## Tech Stack

| Layer | Tool |
|---|---|
| Orchestration | n8n |
| Database | PostgreSQL (Supabase) |
| AI Extraction | OpenAI API (JSON mode) |
| CRM | HubSpot |
| Messaging | Twilio (SMS) |
| Human Approval | Slack |
| Scheduling | Calendly |

## Key Engineering Decisions

- **Idempotency, not just deduplication** — every inbound event is fingerprinted
  and logged with a running `duplicate_count`, rather than silently rejected,
  so duplicate-traffic patterns are measurable, not invisible.
- **AI extraction with honest uncertainty** — the extraction prompt is
  deliberately designed to return `null` rather than guess, paired with a
  confidence score that routes low-confidence leads to human review instead of
  being trusted blindly.
- **Genuine human-in-the-loop, not just a notification** — the Slack approval
  step actually pauses workflow execution until a manager responds, using
  OR-combined risk logic (emergency jobs, high-dollar quotes, low AI
  confidence) to decide what needs a human at all.
- **TCPA-aware consent logging** — every SMS consent decision (granted or
  declined) is logged with the exact disclosure text shown, not just a
  true/false flag, for legal defensibility.
- **Swappable messaging layer** — the entire consent-gating and reminder
  system was built and tested against a simulated send step, so connecting a
  real SMS provider is a one-node change, not a rewrite.
- **Nothing fails silently** — unmatched bookings, unmatched replies, and
  pricing gaps all land in a dedicated exception queue with scheduled Slack
  alerts, rather than disappearing.

## Project Structure

\`\`\`
workflows/    exported n8n workflow JSON files
database/     PostgreSQL schema and analytics views
docs/         architecture notes
\`\`\`

## Status / Roadmap

This is a portfolio build demonstrating production-style patterns. Current
limitations, by design, for this stage of the project:
- SMS sending is simulated pending Twilio A2P 10DLC registration
- Calendly booking confirmations use a stand-in webhook pending a paid
  Calendly plan
- No UI yet exists for resolving items in the exception queue

## About

I'm an AI Automation Engineer based in Lagos, Nigeria, who helps service businesses automate lead-to-revenue workflows, from enquiry capture and qualification to CRM management, appointment booking, quoting, follow-up, and conversion tracking. Open to remote AI automation engineering roles and consulting work. Reach out at steven.fakayode@gmail.com.
