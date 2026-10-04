-- ============================================================
-- WORKFORCE DBA SUITE — Materialized Views (Migration 03)
-- Author  : Emre Kaçar | Database Administrator
-- Purpose : Pre-computed aggregations for reporting.
--           Demonstrates MV creation, unique indexes,
--           REFRESH CONCURRENTLY, and incremental strategies.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- MV 1 : Department Headcount & Payroll Summary
-- Use case : HR dashboard — shows live dept stats
-- Refresh  : Every hour via pg_cron or application scheduler
-- ─────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW mv_dept_headcount AS
SELECT
    d.department_id,
    d.department_name,
    d.location,
    d.budget,
    COUNT(e.employee_id)                               AS total_employees,
    COUNT(e.employee_id) FILTER (WHERE e.status = 'ACTIVE')    AS active_employees,
    COUNT(e.employee_id) FILTER (WHERE e.status = 'ON_LEAVE')  AS on_leave,
    COUNT(e.employee_id) FILTER (WHERE e.status = 'TERMINATED')AS terminated,
    ROUND(AVG(e.salary) FILTER (WHERE e.status = 'ACTIVE'), 2) AS avg_active_salary,
    SUM(e.salary)        FILTER (WHERE e.status = 'ACTIVE')    AS total_payroll,
    ROUND(d.budget - SUM(e.salary) FILTER (WHERE e.status = 'ACTIVE'), 2) AS budget_remaining,
    ROUND(
        CASE WHEN d.budget > 0
             THEN (SUM(e.salary) FILTER (WHERE e.status = 'ACTIVE') / d.budget * 100)
             ELSE 0 END, 2
    )                                                          AS budget_utilization_pct,
    MIN(e.hire_date)                                           AS earliest_hire,
    MAX(e.hire_date)                                           AS latest_hire,
    NOW()                                                      AS last_refreshed
FROM departments d
LEFT JOIN employees e ON d.department_id = e.department_id
GROUP BY d.department_id, d.department_name, d.location, d.budget
WITH DATA;

-- Unique index enables REFRESH CONCURRENTLY (no table lock)
CREATE UNIQUE INDEX idx_mv_dept_headcount_pk
    ON mv_dept_headcount (department_id);

CREATE INDEX idx_mv_dept_payroll
    ON mv_dept_headcount (total_payroll DESC);

-- ─────────────────────────────────────────────────────────────
-- MV 2 : Employee Salary Band Distribution
-- Use case : Compensation analysis — who's under/over band?
-- ─────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW mv_salary_distribution AS
SELECT
    jg.grade_code,
    jg.title,
    jg.min_salary,
    jg.max_salary,
    COUNT(e.employee_id)                                       AS employee_count,
    ROUND(AVG(e.salary), 2)                                    AS avg_salary,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY e.salary)    AS p25_salary,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY e.salary)    AS p50_salary,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY e.salary)    AS p75_salary,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY e.salary)    AS p90_salary,
    MIN(e.salary)                                              AS min_actual_salary,
    MAX(e.salary)                                              AS max_actual_salary,
    COUNT(e.employee_id) FILTER (WHERE e.salary < jg.min_salary) AS below_band,
    COUNT(e.employee_id) FILTER (WHERE e.salary > jg.max_salary) AS above_band,
    NOW()                                                      AS last_refreshed
FROM job_grades jg
LEFT JOIN employees e ON jg.grade_code = e.job_grade AND e.status = 'ACTIVE'
GROUP BY jg.grade_code, jg.title, jg.min_salary, jg.max_salary
WITH DATA;

CREATE UNIQUE INDEX idx_mv_salary_dist_pk
    ON mv_salary_distribution (grade_code);

-- ─────────────────────────────────────────────────────────────
-- MV 3 : Monthly Hiring Trend (Time-Series)
-- Use case : HR analytics — growth by department over time
-- ─────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW mv_hiring_trend AS
SELECT
    DATE_TRUNC('month', e.hire_date)::DATE    AS hire_month,
    d.department_name,
    COUNT(*)                                  AS new_hires,
    ROUND(AVG(e.salary), 2)                   AS avg_entry_salary,
    COUNT(*) FILTER (WHERE e.job_grade LIKE 'L%')  AS individual_contributors,
    COUNT(*) FILTER (WHERE e.job_grade LIKE 'M%')  AS managers,
    COUNT(*) FILTER (WHERE e.job_grade LIKE 'D%')  AS directors,
    NOW()                                     AS last_refreshed
FROM employees e
JOIN departments d ON e.department_id = d.department_id
GROUP BY DATE_TRUNC('month', e.hire_date), d.department_name
ORDER BY hire_month DESC, new_hires DESC
WITH DATA;

CREATE UNIQUE INDEX idx_mv_hiring_trend_pk
    ON mv_hiring_trend (hire_month, department_name);

CREATE INDEX idx_mv_hiring_trend_month
    ON mv_hiring_trend (hire_month DESC);

-- ─────────────────────────────────────────────────────────────
-- MV 4 : Top 20 Slow Queries (DBA Monitoring View)
-- Use case : DBA dashboard — spot performance regressions fast
-- ─────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW mv_slow_query_report AS
SELECT
    snap_time::DATE                              AS snapshot_date,
    query_hash,
    LEFT(query_text, 200)                        AS query_excerpt,
    SUM(calls)                                   AS total_calls,
    ROUND(SUM(total_exec_ms), 2)                 AS total_exec_ms,
    ROUND(AVG(avg_exec_ms), 3)                   AS avg_exec_ms,
    ROUND(MAX(max_exec_ms), 3)                   AS worst_exec_ms,
    ROUND(AVG(cache_hit_ratio) * 100, 2)         AS avg_cache_hit_pct,
    NOW()                                        AS last_refreshed
FROM query_perf_snapshots
WHERE avg_exec_ms > 50                           -- surface queries > 50ms avg
GROUP BY snapshot_date, query_hash, query_excerpt
ORDER BY avg_exec_ms DESC
LIMIT 20
WITH DATA;

CREATE UNIQUE INDEX idx_mv_slow_query_pk
    ON mv_slow_query_report (snapshot_date, query_hash);

-- ─────────────────────────────────────────────────────────────
-- MV 5 : High Performer Leaderboard
-- Use case : Recognition / Succession planning
-- ─────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW mv_performance_leaderboard AS
SELECT
    e.employee_id,
    e.first_name || ' ' || e.last_name          AS full_name,
    d.department_name,
    jg.title                                     AS job_title,
    e.salary,
    COUNT(pr.review_id)                          AS review_count,
    ROUND(AVG(pr.score), 2)                      AS avg_score,
    MAX(pr.score)                                AS best_score,
    MIN(pr.score)                                AS worst_score,
    ROUND(
        (AVG(pr.score) * 0.6 + (e.salary / 100000.0) * 0.4), 4
    )                                            AS composite_rank_score,
    RANK() OVER (ORDER BY AVG(pr.score) DESC)    AS overall_rank,
    RANK() OVER (
        PARTITION BY e.department_id
        ORDER BY AVG(pr.score) DESC
    )                                            AS dept_rank,
    NOW()                                        AS last_refreshed
FROM employees e
JOIN departments d          ON e.department_id = d.department_id
JOIN job_grades jg          ON e.job_grade = jg.grade_code
JOIN performance_reviews pr ON e.employee_id = pr.employee_id
WHERE e.status = 'ACTIVE'
  AND pr.review_date >= NOW() - INTERVAL '2 years'
GROUP BY
    e.employee_id, e.first_name, e.last_name,
    d.department_name, jg.title, e.salary, e.department_id
HAVING COUNT(pr.review_id) >= 1
WITH DATA;

CREATE UNIQUE INDEX idx_mv_perf_leaderboard_pk
    ON mv_performance_leaderboard (employee_id);

CREATE INDEX idx_mv_perf_rank
    ON mv_performance_leaderboard (overall_rank);

-- ─────────────────────────────────────────────────────────────
-- REFRESH PROCEDURE  — call this from pg_cron or scheduler
-- CONCURRENTLY means zero downtime (no lock on the MV)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE refresh_all_materialized_views()
LANGUAGE plpgsql AS $$
DECLARE
    v_start  TIMESTAMPTZ;
    v_end    TIMESTAMPTZ;
BEGIN
    v_start := clock_timestamp();
    RAISE NOTICE '[MV Refresh] Starting at %', v_start;

    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dept_headcount;
    RAISE NOTICE '[MV Refresh] mv_dept_headcount done in % ms',
        EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000;

    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_salary_distribution;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_hiring_trend;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_slow_query_report;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_performance_leaderboard;

    v_end := clock_timestamp();
    RAISE NOTICE '[MV Refresh] All views refreshed in % ms',
        EXTRACT(EPOCH FROM (v_end - v_start)) * 1000;
END;
$$;
