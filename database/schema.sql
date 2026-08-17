CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Safe ENUM creation (won't error if you run twice)
DO $$ BEGIN
  CREATE TYPE lead_status AS ENUM (
    'new','qualifying','disqualified','quoted','booked',
    'in_progress','won','lost','duplicate'
  );
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE consent_status AS ENUM ('granted', 'revoked', 'pending');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE consent_channel AS ENUM ('sms', 'whatsapp', 'email', 'voice');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- Clean start - drop everything in right order
DROP TABLE IF EXISTS consent_logs, lead_events, idempotency_keys, pricing_rules, leads CASCADE;

-- Table: Leads
CREATE TABLE leads (
  lead_id uuid primary key default gen_random_uuid(),
  external_source VARCHAR(50) NOT NULL,
  external_ref_id VARCHAR(255),
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  phone_number VARCHAR(20),
  email VARCHAR(100),
  service_type VARCHAR(100),
  property_type VARCHAR(50),
  zip_code VARCHAR(10),
  city VARCHAR(100),
  state VARCHAR(2),
  timezone VARCHAR(50),
  raw_payload JSONB NOT NULL DEFAULT '{}',
  extracted_data JSONB NOT NULL DEFAULT '{}',
  lead_score  NUMERIC(5,2),
  lead_status lead_status NOT NULL DEFAULT 'new',
  assigned_rep  VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- FIXED: was phone_e164, now phone_number
CREATE INDEX IF NOT EXISTS idx_leads_external_ref ON leads (external_source, external_ref_id);
CREATE INDEX IF NOT EXISTS idx_leads_zip ON leads (zip_code);
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads (lead_status);
CREATE INDEX IF NOT EXISTS idx_leads_phone ON leads (phone_number);

-- Table: lead_events
CREATE TABLE lead_events (
  event_id      BIGSERIAL PRIMARY KEY,
  lead_id       UUID NOT NULL REFERENCES leads(lead_id), -- FIXED: was lead
  event_type    VARCHAR(100) NOT NULL,
  event_payload JSONB NOT NULL DEFAULT '{}',
  actor         VARCHAR(100) NOT NULL DEFAULT 'system',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lead_events_lead_id ON lead_events (lead_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lead_events_type ON lead_events (event_type);
CREATE INDEX IF NOT EXISTS idx_lead_events_created_at ON lead_events (created_at DESC);

-- Table: idempotency_keys
CREATE TABLE idempotency_keys (
    idempotency_key   TEXT PRIMARY KEY,
    source            VARCHAR(50) NOT NULL,
    lead_id           UUID REFERENCES leads(lead_id),
    first_seen_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    duplicate_count   INTEGER NOT NULL DEFAULT 0,
    response_payload  JSONB,
    expires_at        TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '30 days')
);
CREATE INDEX IF NOT EXISTS idx_idempotency_expires ON idempotency_keys (expires_at);

-- Table: consent_logs
CREATE TABLE consent_logs (
    consent_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id               UUID NOT NULL REFERENCES leads(lead_id), -- FIXED: was lead
    channel               consent_channel NOT NULL,
    consent_type          VARCHAR(50) NOT NULL,
    consent_status        consent_status NOT NULL DEFAULT 'pending',
    consent_source        VARCHAR(50),
    consent_text_snapshot TEXT,
    ip_address            INET,
    user_agent            TEXT,
    granted_at            TIMESTAMPTZ,
    revoked_at            TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_consent_lead_id ON consent_logs (lead_id);
CREATE INDEX IF NOT EXISTS idx_consent_channel ON consent_logs (lead_id, channel);

-- Table: pricing_rules
CREATE TABLE pricing_rules (
    pricing_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_type     VARCHAR(100) NOT NULL,
    region_code      VARCHAR(20)  NOT NULL,
    base_price       NUMERIC(10,2) NOT NULL,
    price_unit       VARCHAR(30)  NOT NULL,
    min_price        NUMERIC(10,2),
    max_price        NUMERIC(10,2),
    effective_from   TIMESTAMPTZ NOT NULL DEFAULT now(),
    effective_to     TIMESTAMPTZ,
    source           VARCHAR(50),
    last_verified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pricing_lookup ON pricing_rules (service_type, region_code, is_active);

-- Enable RLS to remove Supabase warning (locked, only service_role can access)
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE consent_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE pricing_rules ENABLE ROW LEVEL SECURITY;