-- ============================================================
-- WORKFORCE DBA SUITE — PL/pgSQL Stored Procedures (04)
-- Author  : Emre Kaçar | Database Administrator
-- Purpose : Business logic encapsulated in the database layer.
--           Demonstrates cursors, exception handling, dynamic SQL,
--           autonomous transactions (via advisory locks), and
--           complex window function reports — Oracle PL/SQL equivalent.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. HIRE EMPLOYEE  — full onboarding with validation & audit
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION hire_employee(
    p_first_name    VARCHAR,
    p_last_name     VARCHAR,
    p_email         VARCHAR,
    p_department_id INT,
    p_job_grade     VARCHAR,
    p_salary        NUMERIC,
    p_hire_date     DATE    DEFAULT CURRENT_DATE,
    p_manager_id    BIGINT  DEFAULT NULL,
    p_location_id   INT     DEFAULT NULL
)
RETURNS TABLE (
    new_employee_id BIGINT,
    full_name       TEXT,
    message         TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_emp_id        BIGINT;
    v_min_sal       NUMERIC;
    v_max_sal       NUMERIC;
    v_dept_exists   BOOLEAN;
BEGIN
    -- 1. Validate department
    SELECT EXISTS (SELECT 1 FROM departments WHERE department_id = p_department_id)
    INTO v_dept_exists;

    IF NOT v_dept_exists THEN
        RAISE EXCEPTION 'Department % does not exist', p_department_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- 2. Validate salary within job grade band
    SELECT min_salary, max_salary
    INTO   v_min_sal, v_max_sal
    FROM   job_grades
    WHERE  grade_code = p_job_grade;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job grade % is invalid', p_job_grade;
    END IF;

    IF p_salary NOT BETWEEN v_min_sal AND v_max_sal THEN
        RAISE EXCEPTION
            'Salary % is outside band for grade % (% – %)',
            p_salary, p_job_grade, v_min_sal, v_max_sal
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3. Email uniqueness check (friendly error)
    IF EXISTS (SELECT 1 FROM employees WHERE email = LOWER(TRIM(p_email))) THEN
        RAISE EXCEPTION 'Email % is already registered', p_email
            USING ERRCODE = 'unique_violation';
    END IF;

    -- 4. Insert employee
    INSERT INTO employees (
        first_name, last_name, email, hire_date,
        department_id, job_grade, salary, manager_id, location_id, status
    ) VALUES (
        TRIM(p_first_name),
        TRIM(p_last_name),
        LOWER(TRIM(p_email)),
        p_hire_date,
        p_department_id,
        p_job_grade,
        p_salary,
        p_manager_id,
        p_location_id,
        'ACTIVE'
    )
    RETURNING employee_id INTO v_emp_id;

    -- 5. Insert initial salary history record
    INSERT INTO salary_history (
        employee_id, old_salary, new_salary,
        change_reason, changed_by, effective_date
    ) VALUES (
        v_emp_id, 0, p_salary,
        'Initial hire salary', current_user, p_hire_date
    );

    -- 6. Return result set
    RETURN QUERY
    SELECT
        v_emp_id,
        TRIM(p_first_name) || ' ' || TRIM(p_last_name),
        FORMAT('Employee hired successfully. ID: %s', v_emp_id);

EXCEPTION
    WHEN OTHERS THEN
        RAISE;                      -- re-raise; caller handles rollback
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 2. BULK SALARY ADJUSTMENT — department-wide raise with cap
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION bulk_salary_adjustment(
    p_department_id INT,
    p_pct_increase  NUMERIC,            -- e.g. 10 = 10%
    p_reason        VARCHAR,
    p_effective_date DATE DEFAULT CURRENT_DATE,
    p_max_budget    NUMERIC DEFAULT NULL -- optional hard cap on total raise cost
)
RETURNS TABLE (
    employee_id     BIGINT,
    full_name       TEXT,
    old_salary      NUMERIC,
    new_salary      NUMERIC,
    delta           NUMERIC,
    status_msg      TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    rec             RECORD;
    v_new_salary    NUMERIC;
    v_total_delta   NUMERIC := 0;
    v_skipped       INT     := 0;
    v_updated       INT     := 0;
    v_max_sal       NUMERIC;
BEGIN
    IF p_pct_increase <= 0 OR p_pct_increase > 50 THEN
        RAISE EXCEPTION 'Percentage must be between 0 and 50. Got: %', p_pct_increase;
    END IF;

    -- Use cursor for large result sets (memory-efficient)
    FOR rec IN
        SELECT e.employee_id,
               e.first_name || ' ' || e.last_name  AS full_name,
               e.salary,
               jg.max_salary
        FROM   employees e
        JOIN   job_grades jg ON e.job_grade = jg.grade_code
        WHERE  e.department_id = p_department_id
          AND  e.status        = 'ACTIVE'
        ORDER  BY e.salary DESC
        FOR UPDATE SKIP LOCKED
    LOOP
        v_new_salary := ROUND(rec.salary * (1 + p_pct_increase / 100.0), 2);

        -- Cap at grade max
        v_new_salary := LEAST(v_new_salary, rec.max_salary);

        -- Budget guard
        IF p_max_budget IS NOT NULL AND
           (v_total_delta + (v_new_salary - rec.salary)) > p_max_budget THEN
            v_skipped := v_skipped + 1;
            RETURN QUERY SELECT
                rec.employee_id,
                rec.full_name::TEXT,
                rec.salary,
                rec.salary,
                0::NUMERIC,
                'SKIPPED: budget cap reached'::TEXT;
            CONTINUE;
        END IF;

        -- Apply update
        UPDATE employees
        SET    salary     = v_new_salary,
               updated_at = NOW()
        WHERE  employee_id = rec.employee_id
          AND  hire_date   >= '2019-01-01';   -- partition key hint

        INSERT INTO salary_history (
            employee_id, old_salary, new_salary,
            change_reason, changed_by, effective_date
        ) VALUES (
            rec.employee_id, rec.salary, v_new_salary,
            p_reason, current_user, p_effective_date
        );

        v_total_delta := v_total_delta + (v_new_salary - rec.salary);
        v_updated     := v_updated + 1;

        RETURN QUERY SELECT
            rec.employee_id,
            rec.full_name::TEXT,
            rec.salary,
            v_new_salary,
            v_new_salary - rec.salary,
            FORMAT('UPDATED: +%s%%', p_pct_increase)::TEXT;
    END LOOP;

    RAISE NOTICE 'Bulk adjustment complete: % updated, % skipped, total delta = %',
        v_updated, v_skipped, v_total_delta;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 3. DEPARTMENT ANALYTICS REPORT — window functions showcase
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_department_analytics(
    p_department_id INT DEFAULT NULL   -- NULL = all departments
)
RETURNS TABLE (
    department_name     VARCHAR,
    employee_name       TEXT,
    job_grade           VARCHAR,
    salary              NUMERIC,
    dept_avg_salary     NUMERIC,
    salary_vs_dept_avg  NUMERIC,
    dept_rank           BIGINT,
    company_rank        BIGINT,
    salary_percentile   NUMERIC,
    running_payroll     NUMERIC,
    yrs_of_service      NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.department_name,
        e.first_name || ' ' || e.last_name,
        e.job_grade,
        e.salary,
        ROUND(AVG(e.salary) OVER (PARTITION BY e.department_id), 2),
        ROUND(e.salary - AVG(e.salary) OVER (PARTITION BY e.department_id), 2),
        RANK() OVER (PARTITION BY e.department_id ORDER BY e.salary DESC),
        RANK() OVER (ORDER BY e.salary DESC),
        ROUND(PERCENT_RANK() OVER (ORDER BY e.salary) * 100, 2),
        SUM(e.salary) OVER (
            PARTITION BY e.department_id
            ORDER BY e.salary DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        ROUND(EXTRACT(EPOCH FROM (NOW() - e.hire_date)) / 86400 / 365.25, 2)
    FROM  employees e
    JOIN  departments d ON e.department_id = d.department_id
    WHERE e.status = 'ACTIVE'
      AND (p_department_id IS NULL OR e.department_id = p_department_id)
    ORDER BY e.department_id, e.salary DESC;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 4. TENURE RETENTION COHORT — month-over-month retention
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_retention_cohort(
    p_cohort_year INT DEFAULT EXTRACT(YEAR FROM NOW())::INT - 2
)
RETURNS TABLE (
    cohort_month        DATE,
    hired               BIGINT,
    still_active        BIGINT,
    retention_rate_pct  NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    WITH cohort AS (
        SELECT DATE_TRUNC('month', hire_date)::DATE AS cohort_month,
               employee_id,
               status
        FROM   employees
        WHERE  EXTRACT(YEAR FROM hire_date) = p_cohort_year
    )
    SELECT
        c.cohort_month,
        COUNT(*)                                       AS hired,
        COUNT(*) FILTER (WHERE c.status = 'ACTIVE')   AS still_active,
        ROUND(
            COUNT(*) FILTER (WHERE c.status = 'ACTIVE')::NUMERIC
            / NULLIF(COUNT(*), 0) * 100, 2
        )                                              AS retention_rate_pct
    FROM cohort c
    GROUP BY c.cohort_month
    ORDER BY c.cohort_month;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 5. INDEX USAGE HEALTH CHECK — DBA utility
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_index_health()
RETURNS TABLE (
    table_name      TEXT,
    index_name      TEXT,
    index_size      TEXT,
    idx_scan        BIGINT,
    idx_tup_read    BIGINT,
    usage_rating    TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.relname::TEXT,
        i.relname::TEXT,
        pg_size_pretty(pg_relation_size(i.oid)),
        s.idx_scan,
        s.idx_tup_read,
        CASE
            WHEN s.idx_scan = 0             THEN '🔴 NEVER USED — consider DROP'
            WHEN s.idx_scan < 100           THEN '🟡 LOW USAGE — monitor'
            WHEN s.idx_scan < 1000          THEN '🟢 MODERATE'
            ELSE                                 '✅ HEAVILY USED'
        END AS usage_rating
    FROM   pg_stat_user_indexes s
    JOIN   pg_index             x ON s.indexrelid = x.indexrelid
    JOIN   pg_class             i ON i.oid        = s.indexrelid
    JOIN   pg_class             t ON t.oid        = s.relid
    WHERE  NOT x.indisprimary
    ORDER  BY s.idx_scan ASC, pg_relation_size(i.oid) DESC;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 6. CAPTURE QUERY PERF SNAPSHOT — called by scheduler
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE capture_query_performance_snapshot()
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO query_perf_snapshots (
        query_hash, query_text, calls,
        total_exec_ms, avg_exec_ms, min_exec_ms, max_exec_ms,
        rows_returned, shared_blks_hit, shared_blks_read
    )
    SELECT
        queryid,
        LEFT(query, 500),
        calls,
        ROUND((total_exec_time)::NUMERIC, 3),
        ROUND((mean_exec_time)::NUMERIC, 3),
        ROUND((min_exec_time)::NUMERIC, 3),
        ROUND((max_exec_time)::NUMERIC, 3),
        rows,
        shared_blks_hit,
        shared_blks_read
    FROM pg_stat_statements
    WHERE calls > 5
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'Performance snapshot captured at %', NOW();
END;
$$;
