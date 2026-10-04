-- ============================================================
-- WORKFORCE DBA SUITE — Şema Kurulumu 01
-- Yazar   : Emre Kaçar (Kanka bu projeyi senin için efsane bir DB mimarisiyle yazdım)
-- Motor   : PostgreSQL 15+
-- Amaç    : İleri seviye DBA tekniklerini (Partitioning, Indexing vb.)
--           kullandığımız kurumsal İK veritabanı.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 0. EKLENTİLER & AYARLAR (Burayı ellemeyelim lazım olur)
-- ─────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;   -- query perf tracking
CREATE EXTENSION IF NOT EXISTS pgcrypto;              -- password hashing
CREATE EXTENSION IF NOT EXISTS pg_trgm;              -- fuzzy text search on names

-- Performans ayarları (bunu LinkedIn'e atarken süsleriz)
-- shared_preload_libraries = 'pg_stat_statements'
-- pg_stat_statements.track = all

-- ─────────────────────────────────────────────────────────────
-- 1. BOYUT / LÜGAT TABLOLARI (Temel tanımlar burada)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE departments (
    department_id   SERIAL PRIMARY KEY,
    department_name VARCHAR(120) NOT NULL UNIQUE,
    location        VARCHAR(100),
    budget          NUMERIC(15,2) NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE job_grades (
    grade_code      VARCHAR(10)  PRIMARY KEY,   -- e.g. 'L1','L2','M1','D1'
    title           VARCHAR(100) NOT NULL,
    min_salary      NUMERIC(12,2) NOT NULL,
    max_salary      NUMERIC(12,2) NOT NULL,
    CONSTRAINT chk_salary_range CHECK (max_salary > min_salary)
);

CREATE TABLE locations (
    location_id   SERIAL PRIMARY KEY,
    city          VARCHAR(80)  NOT NULL,
    country       VARCHAR(80)  NOT NULL DEFAULT 'Turkey',
    office_code   VARCHAR(20)  NOT NULL UNIQUE
);

-- ─────────────────────────────────────────────────────────────
-- 2. ÇALIŞANLAR — İşe giriş yılına göre parçaladık (RANGE partitioning)
-- ─────────────────────────────────────────────────────────────
-- Bu kısım Oracle'daki PARTITION BY RANGE'in aynısı kanka.
-- Mülakatlarda falan DBA sorusu olarak gelir: Tabloyu ful taramayı engeller,
-- eski veriyi arşive atmak çok rahattır (DROP PARTITION falan).

CREATE TABLE employees (
    employee_id     BIGSERIAL,
    first_name      VARCHAR(80)   NOT NULL,
    last_name       VARCHAR(80)   NOT NULL,
    email           VARCHAR(150)  NOT NULL,
    phone           VARCHAR(20),
    hire_date       DATE          NOT NULL,
    department_id   INT           NOT NULL REFERENCES departments(department_id),
    job_grade       VARCHAR(10)   NOT NULL REFERENCES job_grades(grade_code),
    location_id     INT           REFERENCES locations(location_id),
    salary          NUMERIC(12,2) NOT NULL,
    manager_id      BIGINT,                     -- self-referencing
    status          VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE'
                        CHECK (status IN ('ACTIVE','INACTIVE','TERMINATED','ON_LEAVE')),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    PRIMARY KEY (employee_id, hire_date)        -- partition key must be in PK
) PARTITION BY RANGE (hire_date);

-- Yearly partitions (partition pruning kicks in on WHERE hire_date = ...)
CREATE TABLE employees_2019 PARTITION OF employees
    FOR VALUES FROM ('2019-01-01') TO ('2020-01-01');

CREATE TABLE employees_2020 PARTITION OF employees
    FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');

CREATE TABLE employees_2021 PARTITION OF employees
    FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');

CREATE TABLE employees_2022 PARTITION OF employees
    FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');

CREATE TABLE employees_2023 PARTITION OF employees
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE employees_2024 PARTITION OF employees
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE employees_2025 PARTITION OF employees
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Default partition catches anything outside defined ranges
CREATE TABLE employees_default PARTITION OF employees DEFAULT;

-- ─────────────────────────────────────────────────────────────
-- 3. SALARIES — historical record, also partitioned
-- ─────────────────────────────────────────────────────────────
CREATE TABLE salary_history (
    history_id      BIGSERIAL,
    employee_id     BIGINT        NOT NULL,
    old_salary      NUMERIC(12,2) NOT NULL,
    new_salary      NUMERIC(12,2) NOT NULL,
    change_reason   VARCHAR(200),
    changed_by      VARCHAR(100),
    effective_date  DATE          NOT NULL,
    PRIMARY KEY (history_id, effective_date)
) PARTITION BY RANGE (effective_date);

CREATE TABLE salary_history_2020 PARTITION OF salary_history
    FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');
CREATE TABLE salary_history_2021 PARTITION OF salary_history
    FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');
CREATE TABLE salary_history_2022 PARTITION OF salary_history
    FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');
CREATE TABLE salary_history_2023 PARTITION OF salary_history
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE salary_history_2024 PARTITION OF salary_history
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE salary_history_2025 PARTITION OF salary_history
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE salary_history_default PARTITION OF salary_history DEFAULT;

-- ─────────────────────────────────────────────────────────────
-- 4. PERFORMANCE REVIEWS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE performance_reviews (
    review_id       BIGSERIAL PRIMARY KEY,
    employee_id     BIGINT        NOT NULL,
    reviewer_id     BIGINT        NOT NULL,
    review_date     DATE          NOT NULL,
    period_start    DATE          NOT NULL,
    period_end      DATE          NOT NULL,
    score           NUMERIC(4,2)  NOT NULL CHECK (score BETWEEN 1 AND 5),
    rating_label    VARCHAR(30)   GENERATED ALWAYS AS (
                        CASE
                            WHEN score >= 4.5 THEN 'OUTSTANDING'
                            WHEN score >= 3.5 THEN 'EXCEEDS_EXPECTATIONS'
                            WHEN score >= 2.5 THEN 'MEETS_EXPECTATIONS'
                            WHEN score >= 1.5 THEN 'NEEDS_IMPROVEMENT'
                            ELSE 'UNSATISFACTORY'
                        END
                    ) STORED,
    comments        TEXT,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────
-- 5. AUDIT LOG — every sensitive change captured
-- ─────────────────────────────────────────────────────────────
CREATE TABLE audit_log (
    audit_id        BIGSERIAL PRIMARY KEY,
    table_name      VARCHAR(100)  NOT NULL,
    operation       VARCHAR(10)   NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    record_id       BIGINT,
    old_data        JSONB,
    new_data        JSONB,
    changed_by      VARCHAR(100)  NOT NULL DEFAULT current_user,
    changed_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    client_ip       INET,
    application     VARCHAR(100)
);

-- Partial index: only index recent audit records for fast lookups
-- (older records are archived / rarely queried)
-- Regular index on changed_at for time-based audit queries
-- Note: partial indexes require IMMUTABLE functions; use WHERE clause in queries instead
CREATE INDEX idx_audit_recent
    ON audit_log (changed_at DESC, table_name);

-- ─────────────────────────────────────────────────────────────
-- 6. QUERY PERFORMANCE SNAPSHOT TABLE
-- ─────────────────────────────────────────────────────────────
-- DBA stores pg_stat_statements snapshots for trend analysis
CREATE TABLE query_perf_snapshots (
    snap_id         BIGSERIAL PRIMARY KEY,
    snap_time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    query_hash      BIGINT      NOT NULL,
    query_text      TEXT        NOT NULL,
    calls           BIGINT      NOT NULL,
    total_exec_ms   NUMERIC(15,3) NOT NULL,
    avg_exec_ms     NUMERIC(15,3) NOT NULL,
    min_exec_ms     NUMERIC(15,3) NOT NULL,
    max_exec_ms     NUMERIC(15,3) NOT NULL,
    rows_returned   BIGINT,
    shared_blks_hit BIGINT,
    shared_blks_read BIGINT,
    cache_hit_ratio NUMERIC(6,4) GENERATED ALWAYS AS (
                        CASE WHEN (shared_blks_hit + shared_blks_read) = 0 THEN NULL
                             ELSE ROUND(shared_blks_hit::NUMERIC /
                                  (shared_blks_hit + shared_blks_read), 4)
                        END
                    ) STORED
);
