-- ============================================================
-- WORKFORCE DBA SUITE — Index Strategy (Migration 02)
-- Author  : Emre Kaçar | Database Administrator
-- Purpose : Demonstrate advanced indexing — Covering, Partial,
--           Composite, GIN (full-text), BRIN (time-series)
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- EMPLOYEES — Covering Index (Index-Only Scan)
-- INCLUDE columns avoid heap fetch for reporting queries like:
--   SELECT first_name, last_name, salary FROM employees
--   WHERE department_id = 3 AND status = 'ACTIVE'
-- ─────────────────────────────────────────────────────────────
CREATE INDEX idx_emp_dept_status_covering
    ON employees (department_id, status)
    INCLUDE (first_name, last_name, salary, job_grade)
    WHERE status = 'ACTIVE';                    -- Partial: exclude terminated

-- Name search — GIN trigram for fuzzy / LIKE '%kaya%' queries
CREATE INDEX idx_emp_name_trgm
    ON employees USING gin ((first_name || ' ' || last_name) gin_trgm_ops);

-- Email unique index (business rule enforcement + fast lookup)
-- Note: On partitioned tables, UNIQUE indexes must include the partition key.
-- We enforce email uniqueness via stored procedure validation instead.
CREATE INDEX idx_emp_email_unique ON employees (email);

-- Manager hierarchy traversal (recursive CTE walk)
CREATE INDEX idx_emp_manager ON employees (manager_id) WHERE manager_id IS NOT NULL;

-- Hire date — BRIN index: very small, perfect for time-series append-only data
-- Reads 128-page ranges; ideal for reporting "employees hired in Q3 2023"
CREATE INDEX idx_emp_hire_date_brin
    ON employees USING brin (hire_date) WITH (pages_per_range = 128);

-- Composite index for salary band queries
CREATE INDEX idx_emp_salary_grade
    ON employees (job_grade, salary DESC)
    INCLUDE (employee_id, first_name, last_name, department_id);

-- ─────────────────────────────────────────────────────────────
-- PERFORMANCE REVIEWS
-- ─────────────────────────────────────────────────────────────
-- Fast lookup per employee + most recent first
CREATE INDEX idx_review_emp_date
    ON performance_reviews (employee_id, review_date DESC);

-- Filter by rating — partial index only on high performers
CREATE INDEX idx_review_outstanding
    ON performance_reviews (review_date DESC, employee_id)
    WHERE score >= 4.5;

-- ─────────────────────────────────────────────────────────────
-- SALARY HISTORY
-- ─────────────────────────────────────────────────────────────
CREATE INDEX idx_sal_hist_emp_date
    ON salary_history (employee_id, effective_date DESC)
    INCLUDE (old_salary, new_salary, change_reason);

-- ─────────────────────────────────────────────────────────────
-- AUDIT LOG — GIN index on JSONB for forensic queries
-- Enables: WHERE new_data @> '{"status": "TERMINATED"}'
-- ─────────────────────────────────────────────────────────────
CREATE INDEX idx_audit_new_data_gin  ON audit_log USING gin (new_data);
CREATE INDEX idx_audit_old_data_gin  ON audit_log USING gin (old_data);
CREATE INDEX idx_audit_table_op      ON audit_log (table_name, operation, changed_at DESC);

-- ─────────────────────────────────────────────────────────────
-- QUERY PERF SNAPSHOTS
-- ─────────────────────────────────────────────────────────────
CREATE INDEX idx_snap_hash_time
    ON query_perf_snapshots (query_hash, snap_time DESC);

CREATE INDEX idx_snap_slow_queries
    ON query_perf_snapshots (avg_exec_ms DESC, snap_time DESC)
    WHERE avg_exec_ms > 100;                    -- Only surface slow queries

-- ─────────────────────────────────────────────────────────────
-- DEPARTMENTS
-- ─────────────────────────────────────────────────────────────
CREATE INDEX idx_dept_name ON departments (department_name);

-- ─────────────────────────────────────────────────────────────
-- STATISTICS TARGETS — tell planner to be more accurate
-- (DBA best practice: increase for columns with high cardinality)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE employees
    ALTER COLUMN department_id SET STATISTICS 500,
    ALTER COLUMN job_grade     SET STATISTICS 200,
    ALTER COLUMN salary        SET STATISTICS 500;

ALTER TABLE performance_reviews
    ALTER COLUMN employee_id   SET STATISTICS 500;

-- Refresh planner statistics immediately
ANALYZE employees;
ANALYZE performance_reviews;
ANALYZE salary_history;
