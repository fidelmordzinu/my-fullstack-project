---
-- Helper Functions & Extensions
---
-- Used to make array_to_string immutable for the generated full-text search column
CREATE OR REPLACE FUNCTION immutable_array_to_string(text[], text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$ 
    SELECT array_to_string($1, $2); 
$$;

---
-- Core Tables
---

-- 1. Manufacturers (Lookup table for brands)
CREATE TABLE manufacturers (
    id          SERIAL PRIMARY KEY,
    name        TEXT UNIQUE NOT NULL,
    website     TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Component Types (Hierarchical classification system)
CREATE TABLE component_types (
    id              SERIAL PRIMARY KEY,
    name            TEXT UNIQUE NOT NULL,
    parent_type_id  INTEGER REFERENCES component_types(id) ON DELETE SET NULL,
    description     TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Data Sources (Configuration for data scrapers/APIs)
CREATE TABLE data_sources (
    id              SERIAL PRIMARY KEY,
    name            TEXT UNIQUE NOT NULL,
    base_url        TEXT,                          
    download_method TEXT NOT NULL,
    config          JSONB,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Components (Master data table)
CREATE TABLE components (
    id                               BIGSERIAL PRIMARY KEY,
    part_number                      TEXT NOT NULL,
    manufacturer_id                  INTEGER NOT NULL REFERENCES manufacturers(id),
    component_type_id                INTEGER REFERENCES component_types(id),
    title                            TEXT,
    description                      TEXT,                     
    features                         TEXT[],
    datasheet_url                    TEXT,                     
    source_url                       TEXT,
    source_id                        INTEGER REFERENCES data_sources(id), 
    last_scraped_at                  TIMESTAMPTZ,
    
    -- Semi-structured JSONB Specifications
    thermal_packaging_data           JSONB NOT NULL DEFAULT '{}',
    electrical_characteristics       JSONB NOT NULL DEFAULT '{}',
    absolute_max_ratings             JSONB NOT NULL DEFAULT '{}',
    recommended_operating_conditions JSONB NOT NULL DEFAULT '{}', 
    pinout_description               JSONB NOT NULL DEFAULT '{}',   
    application_information          JSONB NOT NULL DEFAULT '{}',   
    
    revision                         TEXT,
    revision_date                    DATE,
    created_at                       TIMESTAMPTZ DEFAULT NOW(),
    updated_at                       TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT unique_component UNIQUE (part_number, manufacturer_id)
);

-- Full-Text Search Vector Generation & Indexing
ALTER TABLE components ADD COLUMN search_vector TSVECTOR
  GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(part_number, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(title, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'C') ||
    setweight(to_tsvector('english', immutable_array_to_string(features, ' ')), 'C')
  ) STORED;

CREATE INDEX idx_components_search ON components USING GIN (search_vector);

-- Performance B-Tree Indexes
CREATE INDEX idx_components_part_number ON components (part_number);
CREATE INDEX idx_components_manufacturer ON components (manufacturer_id);
CREATE INDEX idx_components_type ON components (component_type_id);
CREATE INDEX idx_components_updated ON components (updated_at DESC);

---
-- Operational & Telemetry Tables
---

-- 5. Scrape Logs (Pipeline health tracking)
CREATE TABLE scrape_logs (
    id              BIGSERIAL PRIMARY KEY,
    source_id       INTEGER REFERENCES data_sources(id),
    target_url      TEXT NOT NULL,
    component_id    BIGINT REFERENCES components(id) ON DELETE SET NULL,
    status          TEXT NOT NULL,
    error_message   TEXT,
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    finished_at     TIMESTAMPTZ
);

-- 6. Component History (Data audit ledger)
CREATE TABLE component_history (
    id              BIGSERIAL PRIMARY KEY,
    component_id    BIGINT NOT NULL REFERENCES components(id) ON DELETE CASCADE,
    changed_by      TEXT,
    changed_at      TIMESTAMPTZ DEFAULT NOW(),
    old_data        JSONB,
    new_data        JSONB
);