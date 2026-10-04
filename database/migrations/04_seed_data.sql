-- ============================================================
-- WORKFORCE DBA SUITE — Sample Data (Migration 06)
-- Author  : Emre Kaçar | Database Administrator
-- Purpose : Realistic seed data for demo & LinkedIn showcase
-- ============================================================

-- ─── DEPARTMENTS ────────────────────────────────────────────
INSERT INTO departments (department_name, location, budget) VALUES
('Engineering',            'Istanbul',   15000000),
('Product Management',     'Istanbul',    8000000),
('Data & Analytics',       'Ankara',      6000000),
('Human Resources',        'Istanbul',    3000000),
('Finance',                'Istanbul',    5000000),
('Marketing',              'Istanbul',    4000000),
('Customer Success',       'Izmir',       3500000),
('DevOps & Infrastructure','Istanbul',    7000000),
('Legal & Compliance',     'Istanbul',    2500000),
('Sales',                  'Izmir',       9000000);

-- ─── JOB GRADES ─────────────────────────────────────────────
INSERT INTO job_grades (grade_code, title, min_salary, max_salary) VALUES
('L1', 'Junior Engineer / Analyst',    25000,  50000),
('L2', 'Mid-level Engineer / Analyst', 50001,  90000),
('L3', 'Senior Engineer / Analyst',    90001, 140000),
('L4', 'Staff Engineer / Lead',       140001, 200000),
('M1', 'Engineering Manager',         180000, 280000),
('M2', 'Senior Manager',              280001, 380000),
('D1', 'Director',                    380001, 550000),
('D2', 'Senior Director / VP',        550001, 800000),
('C1', 'C-Level / Executive',         800001,2000000);

-- ─── LOCATIONS ──────────────────────────────────────────────
INSERT INTO locations (city, country, office_code) VALUES
('Istanbul',  'Turkey', 'IST-01'),
('Ankara',    'Turkey', 'ANK-01'),
('Izmir',     'Turkey', 'IZM-01'),
('Berlin',    'Germany','BRL-01'),
('London',    'UK',     'LDN-01');

-- ─── EMPLOYEES (200 realistic records across all partitions) ─
-- Disable budget trigger temporarily for seeding
DO $$
DECLARE
    first_names TEXT[] := ARRAY[
        'Emre','Ahmet','Mehmet','Ali','Mustafa','Hüseyin','İbrahim','Hasan',
        'Ayşe','Fatma','Zeynep','Elif','Selin','Melis','Deniz','Ece',
        'Oğuz','Serkan','Burak','Onur','Kaan','Mert','Furkan','Berkay',
        'Yasemin','Özlem','Gizem','Şeyma','Neslihan','Büşra','Cansu','Aslı'
    ];
    last_names  TEXT[] := ARRAY[
        'Kaçar','Yılmaz','Kaya','Demir','Şahin','Çelik','Arslan','Doğan',
        'Kılıç','Aslan','Öztürk','Aydın','Özdemir','Şimşek','Yıldız','Erdoğan',
        'Çetin','Aktaş','Kurt','Güngör','Polat','Koç','Acar','Çakır'
    ];
    hire_years  INT[] := ARRAY[2019,2020,2021,2022,2023,2024,2025];
    grades      TEXT[] := ARRAY['L1','L1','L2','L2','L2','L3','L3','L4','M1','M2','D1'];
    dept_ids    INT[] := ARRAY[1,2,3,4,5,6,7,8,9,10];
    loc_ids     INT[] := ARRAY[1,2,3,1,1];

    v_fname     TEXT;
    v_lname     TEXT;
    v_email     TEXT;
    v_grade     TEXT;
    v_dept      INT;
    v_loc       INT;
    v_hire_year INT;
    v_hire_date DATE;
    v_salary    NUMERIC;
    v_min_sal   NUMERIC;
    v_max_sal   NUMERIC;
    v_status    TEXT;
    v_statuses  TEXT[] := ARRAY['ACTIVE','ACTIVE','ACTIVE','ACTIVE','ACTIVE','ACTIVE','ACTIVE','ACTIVE','ON_LEAVE','TERMINATED'];
    i           INT;
BEGIN
    FOR i IN 1..200 LOOP
        v_fname     := first_names[1 + MOD(i * 7  + 3, array_length(first_names, 1))];
        v_lname     := last_names [1 + MOD(i * 11 + 5, array_length(last_names,  1))];
        v_email     := LOWER(v_fname || '.' || v_lname || i || '@ek-hr.dev');
        v_grade     := grades     [1 + MOD(i * 3,      array_length(grades,      1))];
        v_dept      := dept_ids   [1 + MOD(i * 13,     array_length(dept_ids,    1))];
        v_loc       := loc_ids    [1 + MOD(i * 17,     array_length(loc_ids,     1))];
        v_hire_year := hire_years [1 + MOD(i * 5,      array_length(hire_years,  1))];
        v_hire_date := MAKE_DATE(v_hire_year, 1 + MOD(i, 12), 1 + MOD(i * 7, 28));
        v_status    := v_statuses [1 + MOD(i * 19,     array_length(v_statuses,  1))];

        SELECT min_salary, max_salary INTO v_min_sal, v_max_sal
        FROM job_grades WHERE grade_code = v_grade;

        v_salary := ROUND(
            v_min_sal + (v_max_sal - v_min_sal) * (0.3 + (MOD(i * 37, 70)::NUMERIC / 100)), 2
        );

        INSERT INTO employees (
            first_name, last_name, email, hire_date,
            department_id, job_grade, salary, location_id, status
        ) VALUES (
            v_fname, v_lname, v_email, v_hire_date,
            v_dept, v_grade, v_salary, v_loc, v_status
        );
    END LOOP;
END;
$$;

-- ─── PERFORMANCE REVIEWS (recent 2 years, multiple per employee) ─
INSERT INTO performance_reviews (employee_id, reviewer_id, review_date, period_start, period_end, score, comments)
SELECT
    e.employee_id,
    (SELECT reviewer.employee_id FROM employees reviewer
     WHERE reviewer.department_id = e.department_id
       AND reviewer.employee_id <> e.employee_id
     ORDER BY RANDOM() LIMIT 1),
    review_date,
    (review_date - INTERVAL '6 months')::DATE,
    review_date,
    ROUND((3.0 + RANDOM() * 2.0)::NUMERIC, 2),
    'Semi-annual performance review - ' || TO_CHAR(review_date, 'Month YYYY')
FROM
    employees e,
    (VALUES
        (CURRENT_DATE - INTERVAL '18 months'),
        (CURRENT_DATE - INTERVAL '12 months'),
        (CURRENT_DATE - INTERVAL '6 months')
    ) AS reviews(review_date)
WHERE e.status IN ('ACTIVE', 'ON_LEAVE')
LIMIT 400;

-- ─── QUERY PERF SNAPSHOTS (demo data for DBA dashboard) ─────
INSERT INTO query_perf_snapshots (
    snap_time, query_hash, query_text, calls,
    total_exec_ms, avg_exec_ms, min_exec_ms, max_exec_ms,
    rows_returned, shared_blks_hit, shared_blks_read
)
SELECT
    NOW() - (n || ' hours')::INTERVAL,
    ABS(HASHTEXT('query_' || (MOD(n, 10))::TEXT)),
    CASE MOD(n, 10)
        WHEN 0 THEN 'SELECT * FROM employees WHERE department_id = $1 AND status = $2'
        WHEN 1 THEN 'SELECT e.*, d.department_name FROM employees e JOIN departments d ON e.department_id = d.department_id WHERE e.salary > $1'
        WHEN 2 THEN 'SELECT AVG(score) FROM performance_reviews WHERE employee_id = $1'
        WHEN 3 THEN 'UPDATE employees SET salary = $1 WHERE employee_id = $2'
        WHEN 4 THEN 'SELECT * FROM mv_dept_headcount ORDER BY total_payroll DESC'
        WHEN 5 THEN 'SELECT first_name, last_name, salary FROM employees WHERE job_grade = $1 ORDER BY salary DESC'
        WHEN 6 THEN 'INSERT INTO salary_history VALUES ($1, $2, $3, $4, $5, $6)'
        WHEN 7 THEN 'SELECT COUNT(*), AVG(salary) FROM employees WHERE hire_date BETWEEN $1 AND $2'
        WHEN 8 THEN 'SELECT * FROM mv_performance_leaderboard LIMIT 20'
        ELSE        'SELECT * FROM audit_log WHERE table_name = $1 AND changed_at > NOW() - INTERVAL ''7 days'''
    END,
    50 + (n * 7),
    (50 + (n * 7)) * (5 + MOD(n, 50)),
    5 + MOD(n * 3, 450),
    0.5,
    800 + MOD(n, 2000),
    100 + MOD(n * 13, 500),
    10 + MOD(n, 200),
    900 + MOD(n * 7, 500),
    MOD(n * 3, 100)
FROM generate_series(1, 72) AS gs(n);

-- ─── REFRESH MVs AFTER SEED ──────────────────────────────────
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dept_headcount;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_salary_distribution;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_hiring_trend;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_slow_query_report;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_performance_leaderboard;
