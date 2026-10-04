-- ============================================================
-- WORKFORCE DBA SUITE — Triggers (Migration 05)
-- Author  : Emre Kaçar | Database Administrator
-- Purpose : Automated, database-level business rules.
--           Demonstrates BEFORE/AFTER, ROW/STATEMENT triggers,
--           JSONB audit capture, and cascading logic —
--           equivalent to Oracle's DML triggers.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. AUTO-UPDATE updated_at TIMESTAMP  (BEFORE UPDATE)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_employees_updated_at
    BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- ─────────────────────────────────────────────────────────────
-- 2. SALARY CHANGE AUTO-LOG  (AFTER UPDATE)
-- When salary changes on employees, automatically insert into
-- salary_history — zero-risk, database-enforced audit trail.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_salary_change_log()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    -- Only fire when salary actually changed
    IF OLD.salary IS DISTINCT FROM NEW.salary THEN
        INSERT INTO salary_history (
            employee_id, old_salary, new_salary,
            change_reason, changed_by, effective_date
        ) VALUES (
            NEW.employee_id,
            OLD.salary,
            NEW.salary,
            COALESCE(
                current_setting('app.change_reason', TRUE),
                'Direct update'
            ),
            current_user,
            CURRENT_DATE
        );
    END IF;
    RETURN NULL;    -- AFTER trigger returns NULL
END;
$$;

CREATE TRIGGER trg_employees_salary_log
    AFTER UPDATE OF salary ON employees
    FOR EACH ROW EXECUTE FUNCTION trg_salary_change_log();

-- ─────────────────────────────────────────────────────────────
-- 3. GENERIC AUDIT TRIGGER  (AFTER INSERT/UPDATE/DELETE)
-- Captures full JSONB snapshot of old and new row data.
-- This is a reusable trigger — attach to any sensitive table.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_generic_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_old_data  JSONB;
    v_new_data  JSONB;
    v_record_id BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_old_data  := to_jsonb(OLD);
        v_new_data  := NULL;
        v_record_id := (OLD::text::jsonb ->> 'employee_id')::BIGINT;
    ELSIF TG_OP = 'INSERT' THEN
        v_old_data  := NULL;
        v_new_data  := to_jsonb(NEW);
        v_record_id := (NEW::text::jsonb ->> 'employee_id')::BIGINT;
    ELSE -- UPDATE
        v_old_data  := to_jsonb(OLD);
        v_new_data  := to_jsonb(NEW);
        v_record_id := (NEW::text::jsonb ->> 'employee_id')::BIGINT;

        -- Skip if nothing actually changed (prevents noise from meaningless updates)
        IF v_old_data = v_new_data THEN
            RETURN NULL;
        END IF;
    END IF;

    INSERT INTO audit_log (
        table_name, operation, record_id,
        old_data, new_data, changed_by,
        client_ip, application
    ) VALUES (
        TG_TABLE_NAME,
        TG_OP,
        v_record_id,
        v_old_data,
        v_new_data,
        current_user,
        inet_client_addr(),
        current_setting('app.application_name', TRUE)
    );

    RETURN NULL;
END;
$$;

-- Attach audit trigger to employees
CREATE TRIGGER trg_employees_audit
    AFTER INSERT OR UPDATE OR DELETE ON employees
    FOR EACH ROW EXECUTE FUNCTION trg_generic_audit();

-- ─────────────────────────────────────────────────────────────
-- 4. PREVENT TERMINATION WITHOUT REVIEW  (BEFORE UPDATE)
-- Business rule: An employee cannot be TERMINATED unless they
-- have had at least one performance review.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_validate_termination()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_review_count INT;
BEGIN
    IF OLD.status != 'TERMINATED' AND NEW.status = 'TERMINATED' THEN
        SELECT COUNT(*) INTO v_review_count
        FROM   performance_reviews
        WHERE  employee_id = NEW.employee_id;

        IF v_review_count = 0 THEN
            RAISE EXCEPTION
                'Cannot terminate employee % (%): no performance review on record.',
                NEW.employee_id,
                NEW.first_name || ' ' || NEW.last_name
                USING ERRCODE = 'integrity_constraint_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_employees_validate_termination
    BEFORE UPDATE OF status ON employees
    FOR EACH ROW EXECUTE FUNCTION trg_validate_termination();

-- ─────────────────────────────────────────────────────────────
-- 5. ENFORCE MANAGER MUST BE SENIOR  (BEFORE INSERT/UPDATE)
-- A manager_id must reference an employee at grade M1 or above.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_validate_manager()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_mgr_grade VARCHAR(10);
BEGIN
    IF NEW.manager_id IS NOT NULL THEN
        SELECT job_grade INTO v_mgr_grade
        FROM   employees
        WHERE  employee_id = NEW.manager_id
          AND  status = 'ACTIVE'
        LIMIT  1;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Manager ID % not found or inactive.', NEW.manager_id;
        END IF;

        IF v_mgr_grade NOT LIKE 'M%' AND v_mgr_grade NOT LIKE 'D%' THEN
            RAISE EXCEPTION
                'Manager (ID %) must hold a Manager or Director grade. Found: %',
                NEW.manager_id, v_mgr_grade
                USING ERRCODE = 'integrity_constraint_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_employees_validate_manager
    BEFORE INSERT OR UPDATE OF manager_id ON employees
    FOR EACH ROW EXECUTE FUNCTION trg_validate_manager();

-- ─────────────────────────────────────────────────────────────
-- 6. DEPARTMENT BUDGET GUARD  (BEFORE INSERT/UPDATE — salary)
-- Prevents adding employee if dept payroll would exceed budget
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_budget_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_current_payroll   NUMERIC;
    v_dept_budget       NUMERIC;
    v_proposed_delta    NUMERIC;
BEGIN
    SELECT COALESCE(SUM(e.salary), 0), d.budget
    INTO   v_current_payroll, v_dept_budget
    FROM   departments d
    LEFT JOIN employees e
           ON e.department_id = d.department_id AND e.status = 'ACTIVE'
    WHERE  d.department_id = NEW.department_id
    GROUP  BY d.budget;

    -- Delta: new salary vs old salary (0 on INSERT)
    v_proposed_delta := NEW.salary - COALESCE(OLD.salary, 0);

    IF (v_current_payroll + v_proposed_delta) > v_dept_budget THEN
        RAISE EXCEPTION
            'Budget exceeded for dept %. Current payroll: %, Proposed addition: %, Budget: %',
            NEW.department_id,
            v_current_payroll,
            v_proposed_delta,
            v_dept_budget
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

-- Intentionally commented out for demo — uncomment to enable hard budget enforcement
-- CREATE TRIGGER trg_employees_budget_guard
--     BEFORE INSERT OR UPDATE OF salary, department_id ON employees
--     FOR EACH ROW EXECUTE FUNCTION trg_budget_guard();

-- ─────────────────────────────────────────────────────────────
-- 7. MV AUTO-REFRESH TRIGGER  (AFTER STATEMENT)
-- After bulk INSERT/UPDATE on employees, queue MV refresh.
-- Uses pg_notify so the application can refresh asynchronously.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_notify_mv_refresh()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify('mv_refresh_needed', TG_TABLE_NAME);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_employees_notify_mv
    AFTER INSERT OR UPDATE OR DELETE ON employees
    FOR EACH STATEMENT EXECUTE FUNCTION trg_notify_mv_refresh();
