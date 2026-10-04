"""
EK HR DB Intelligence — FastAPI Backend
Yazar : Emre Kaçar (Kankam, API tarafını böyle akıcı yazdım)
"""
from __future__ import annotations

import os, json, time
from contextlib import asynccontextmanager
from typing import Any

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

load_dotenv()

# ─── DB Connection ───────────────────────────────────────────
DB_CONFIG = dict(
    host     = os.getenv("DB_HOST", "localhost"),
    port     = int(os.getenv("DB_PORT", 5432)),
    dbname   = os.getenv("DB_NAME", "ek_hr_db"),
    user     = os.getenv("DB_USER", "postgres"),
    password = os.getenv("DB_PASS", "postgres"),
)

def get_conn():
    return psycopg2.connect(**DB_CONFIG)

def query(sql: str, params=None) -> list[dict]:
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            t0 = time.perf_counter()
            cur.execute(sql, params)
            rows = cur.fetchall()
            elapsed = round((time.perf_counter() - t0) * 1000, 3)
        conn.commit()
        return [dict(r) for r in rows], elapsed
    finally:
        conn.close()

def execute(sql: str, params=None):
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            t0 = time.perf_counter()
            cur.execute(sql, params)
            rows = cur.fetchall() if cur.description else []
            elapsed = round((time.perf_counter() - t0) * 1000, 3)
        conn.commit()
        return [dict(r) for r in rows], elapsed
    finally:
        conn.close()

# ─── App ─────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    yield

app = FastAPI(
    title="EK HR DB Intelligence API",
    description="Enterprise HR Database Performance & Analytics Platform",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Serve Frontend ──────────────────────────────────────────
FRONTEND_DIR = os.path.join(os.path.dirname(__file__), "..", "frontend")
# Statics will be mounted at the end of the file to not shadow API routes.

# ═══════════════════════════════════════════════════════════════
# DASHBOARD OVERVIEW
# ═══════════════════════════════════════════════════════════════
@app.get("/api/overview")
def get_overview():
    """Dashboard için yukarıdaki ana metrik kartlarını doldurur."""
    rows, ms = query("""
        SELECT
            (SELECT COUNT(*) FROM employees WHERE status = 'ACTIVE')             AS active_employees,
            (SELECT COUNT(*) FROM employees)                                      AS total_employees,
            (SELECT COUNT(*) FROM departments)                                    AS total_departments,
            (SELECT ROUND(SUM(salary),2) FROM employees WHERE status='ACTIVE')   AS total_payroll,
            (SELECT ROUND(AVG(salary),2) FROM employees WHERE status='ACTIVE')   AS avg_salary,
            (SELECT COUNT(*) FROM performance_reviews
             WHERE review_date >= NOW() - INTERVAL '6 months')                   AS recent_reviews,
            (SELECT COUNT(*) FROM audit_log
             WHERE changed_at >= NOW() - INTERVAL '24 hours')                    AS audit_events_24h,
            (SELECT COUNT(*) FROM employees WHERE status='TERMINATED')           AS terminated,
            (SELECT COUNT(*) FROM employees WHERE status='ON_LEAVE')             AS on_leave,
            (SELECT ROUND(AVG(score),2) FROM performance_reviews
             WHERE review_date >= NOW() - INTERVAL '12 months')                  AS avg_perf_score
    """)
    data = rows[0] if rows else {}
    data["query_exec_ms"] = ms
    return data

# ═══════════════════════════════════════════════════════════════
# DEPARTMENT ANALYTICS
# ═══════════════════════════════════════════════════════════════
@app.get("/api/departments")
def get_departments():
    """Materialized view'dan çeker: departman kafa sayısı + maaş yükü + bütçe."""
    rows, ms = query("""
        SELECT * FROM mv_dept_headcount
        ORDER BY total_payroll DESC NULLS LAST
    """)
    return {"data": rows, "query_exec_ms": ms, "source": "mv_dept_headcount"}

@app.get("/api/departments/{dept_id}/employees")
def get_dept_employees(dept_id: int):
    rows, ms = query("""
        SELECT
            e.employee_id, e.first_name, e.last_name,
            e.email, e.hire_date, e.salary, e.job_grade,
            jg.title AS job_title, e.status,
            ROUND(EXTRACT(EPOCH FROM (NOW()-e.hire_date))/86400/365.25,1) AS years_of_service
        FROM employees e
        JOIN job_grades jg ON e.job_grade = jg.grade_code
        WHERE e.department_id = %s
        ORDER BY e.salary DESC
    """, (dept_id,))
    return {"data": rows, "query_exec_ms": ms}

# ═══════════════════════════════════════════════════════════════
# SALARY ANALYTICS
# ═══════════════════════════════════════════════════════════════
@app.get("/api/salary/distribution")
def get_salary_distribution():
    rows, ms = query("SELECT * FROM mv_salary_distribution ORDER BY min_salary")
    return {"data": rows, "query_exec_ms": ms, "source": "mv_salary_distribution"}

@app.get("/api/salary/history/{employee_id}")
def get_salary_history(employee_id: int):
    rows, ms = query("""
        SELECT * FROM salary_history
        WHERE employee_id = %s
        ORDER BY effective_date DESC
        LIMIT 20
    """, (employee_id,))
    return {"data": rows, "query_exec_ms": ms}

# ═══════════════════════════════════════════════════════════════
# HIRING TREND
# ═══════════════════════════════════════════════════════════════
@app.get("/api/hiring/trend")
def get_hiring_trend():
    rows, ms = query("""
        SELECT * FROM mv_hiring_trend
        ORDER BY hire_month DESC
        LIMIT 36
    """)
    return {"data": rows, "query_exec_ms": ms, "source": "mv_hiring_trend"}

# ═══════════════════════════════════════════════════════════════
# PERFORMANCE
# ═══════════════════════════════════════════════════════════════
@app.get("/api/performance/leaderboard")
def get_leaderboard(limit: int = Query(20, ge=1, le=100)):
    rows, ms = query(f"""
        SELECT * FROM mv_performance_leaderboard
        ORDER BY overall_rank
        LIMIT %s
    """, (limit,))
    return {"data": rows, "query_exec_ms": ms, "source": "mv_performance_leaderboard"}

@app.get("/api/performance/retention")
def get_retention(year: int = Query(None)):
    import datetime
    if year is None:
        year = datetime.date.today().year - 2
    rows, ms = query(
        "SELECT * FROM get_retention_cohort(%s) ORDER BY cohort_month",
        (year,)
    )
    return {"data": rows, "query_exec_ms": ms, "cohort_year": year}

# ═══════════════════════════════════════════════════════════════
# DATABASE HEALTH (DBA DASHBOARD)
# ═══════════════════════════════════════════════════════════════
@app.get("/api/dba/index-health")
def get_index_health():
    rows, ms = query("SELECT * FROM check_index_health()")
    return {"data": rows, "query_exec_ms": ms}

@app.get("/api/dba/slow-queries")
def get_slow_queries():
    rows, ms = query("""
        SELECT * FROM mv_slow_query_report
        ORDER BY avg_exec_ms DESC
    """)
    return {"data": rows, "query_exec_ms": ms}

@app.get("/api/dba/table-stats")
def get_table_stats():
    rows, ms = query("""
        SELECT
            schemaname,
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
            pg_size_pretty(pg_relation_size(schemaname||'.'||tablename))       AS table_size,
            pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename))        AS index_size,
            n_live_tup     AS live_rows,
            n_dead_tup     AS dead_rows,
            last_vacuum,
            last_autovacuum,
            last_analyze
        FROM pg_stat_user_tables
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
    """)
    return {"data": rows, "query_exec_ms": ms}

@app.get("/api/dba/partition-info")
def get_partition_info():
    rows, ms = query("""
        SELECT
            parent.relname                                          AS parent_table,
            child.relname                                          AS partition_name,
            pg_size_pretty(pg_relation_size(child.oid))           AS partition_size,
            pg_stat_user_tables.n_live_tup                        AS live_rows,
            pg_get_expr(child.relpartbound, child.oid, TRUE)      AS partition_range
        FROM pg_inherits
        JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
        JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
        LEFT JOIN pg_stat_user_tables
               ON pg_stat_user_tables.relname = child.relname
        WHERE parent.relname IN ('employees','salary_history')
        ORDER BY parent.relname, child.relname
    """)
    return {"data": rows, "query_exec_ms": ms}

@app.get("/api/dba/cache-hit")
def get_cache_hit():
    rows, ms = query("""
        SELECT
            relname,
            heap_blks_hit,
            heap_blks_read,
            CASE WHEN (heap_blks_hit + heap_blks_read) = 0 THEN NULL
                 ELSE ROUND(heap_blks_hit::NUMERIC / (heap_blks_hit + heap_blks_read) * 100, 2)
            END AS cache_hit_pct
        FROM pg_statio_user_tables
        ORDER BY (heap_blks_hit + heap_blks_read) DESC
        LIMIT 15
    """)
    return {"data": rows, "query_exec_ms": ms}

@app.get("/api/dba/audit-log")
def get_audit_log(limit: int = Query(50, ge=1, le=200)):
    rows, ms = query("""
        SELECT
            audit_id, table_name, operation,
            record_id, changed_by, changed_at,
            client_ip, application,
            old_data, new_data
        FROM audit_log
        ORDER BY changed_at DESC
        LIMIT %s
    """, (limit,))
    # Serialize JSONB fields
    for r in rows:
        if r.get("old_data"): r["old_data"] = dict(r["old_data"])
        if r.get("new_data"): r["new_data"] = dict(r["new_data"])
    return {"data": rows, "query_exec_ms": ms}

# ═══════════════════════════════════════════════════════════════
# EXPLAIN ANALYZE  (DBA showcase — query plan visualization)
# ═══════════════════════════════════════════════════════════════
SAFE_QUERIES = {
    "dept_headcount": """
        SELECT d.department_name, COUNT(e.employee_id) AS headcount,
               SUM(e.salary) AS payroll
        FROM departments d
        LEFT JOIN employees e ON d.department_id = e.department_id
          AND e.status = 'ACTIVE'
        GROUP BY d.department_name
        ORDER BY payroll DESC
    """,
    "slow_join": """
        SELECT e.first_name, e.last_name, e.salary,
               AVG(pr.score) OVER (PARTITION BY e.department_id) AS dept_avg_score
        FROM employees e
        JOIN performance_reviews pr ON e.employee_id = pr.employee_id
        WHERE e.salary > 80000
    """,
    "partition_scan": """
        SELECT employee_id, first_name, last_name, hire_date, salary
        FROM employees
        WHERE hire_date BETWEEN '2023-01-01' AND '2023-12-31'
          AND status = 'ACTIVE'
        ORDER BY salary DESC
        LIMIT 50
    """,
    "mv_vs_base": """
        SELECT *
        FROM mv_dept_headcount
        ORDER BY total_payroll DESC
    """,
}

@app.get("/api/dba/explain/{query_key}")
def explain_query(query_key: str):
    if query_key not in SAFE_QUERIES:
        raise HTTPException(404, f"Query key '{query_key}' not found. "
                                 f"Available: {list(SAFE_QUERIES.keys())}")
    sql = SAFE_QUERIES[query_key]
    rows, ms = query(
        f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {sql}"
    )
    plan = rows[0]["QUERY PLAN"] if rows else []
    return {
        "query_key": query_key,
        "sql": sql.strip(),
        "plan": plan,
        "explain_exec_ms": ms,
    }

@app.get("/api/dba/explain-keys")
def list_explain_keys():
    return {"keys": list(SAFE_QUERIES.keys())}

# ═══════════════════════════════════════════════════════════════
# EMPLOYEES  (CRUD sample)
# ═══════════════════════════════════════════════════════════════
@app.get("/api/employees")
def list_employees(
    search: str = Query(None),
    department_id: int = Query(None),
    status: str = Query(None),
    limit: int = Query(50, ge=1, le=200),
):
    filters, params = [], []

    if search:
        filters.append(
            "(first_name || ' ' || last_name) ILIKE %s OR email ILIKE %s"
        )
        params += [f"%{search}%", f"%{search}%"]
    if department_id:
        filters.append("e.department_id = %s")
        params.append(department_id)
    if status:
        filters.append("e.status = %s")
        params.append(status.upper())

    where = ("WHERE " + " AND ".join(filters)) if filters else ""
    params.append(limit)

    rows, ms = query(f"""
        SELECT
            e.employee_id, e.first_name, e.last_name, e.email,
            e.hire_date, e.salary, e.job_grade, jg.title AS job_title,
            e.status, d.department_name,
            ROUND(EXTRACT(EPOCH FROM (NOW()-e.hire_date))/86400/365.25,1) AS yrs_of_service
        FROM employees e
        JOIN departments d ON e.department_id = d.department_id
        JOIN job_grades jg ON e.job_grade = jg.grade_code
        {where}
        ORDER BY e.salary DESC
        LIMIT %s
    """, params)
    return {"data": rows, "count": len(rows), "query_exec_ms": ms}

@app.get("/api/employees/{emp_id}")
def get_employee(emp_id: int):
    rows, ms = query("""
        SELECT
            e.*, d.department_name, jg.title AS job_title,
            l.city, l.country,
            ROUND(EXTRACT(EPOCH FROM (NOW()-e.hire_date))/86400/365.25,2) AS yrs_of_service
        FROM employees e
        JOIN departments d ON e.department_id = d.department_id
        JOIN job_grades jg ON e.job_grade = jg.grade_code
        LEFT JOIN locations l ON e.location_id = l.location_id
        WHERE e.employee_id = %s
    """, (emp_id,))
    if not rows:
        raise HTTPException(404, "Employee not found")
    return rows[0]

if os.path.isdir(FRONTEND_DIR):
    app.mount("/", StaticFiles(directory=FRONTEND_DIR, html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
