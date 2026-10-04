EK HR DB IntelligenceEnterprise-level HR Database Performance & Analytics Platform built on PostgreSQL 16.This project demonstrates advanced Database Administration (DBA), PL/pgSQL development, performance tuning, and data analytics pipeline techniques on a real-world HR schema. It features a complete end-to-end architecture: PostgreSQL core engine, FastAPI backend services, and a live DBA performance monitoring dashboard.📌 Key Architectural HighlightsRange Partitioning: Core employees dataset partitioned by hire_date (Yearly bounds + default partition).Indexing Strategy: Implementation of Covering Indexes (INCLUDE), BRIN (time-series), GIN (JSONB forensics & pg_trgm fuzzy search), and Partial Indexes (status = 'ACTIVE').Materialized Views: 5 pre-calculated MViews managed with REFRESH CONCURRENTLY for non-blocking analytical reporting.PL/pgSQL Automation: 6 procedures/functions utilizing cursors, dynamic SQL, custom error handling, and window functions (RANK, PERCENT_RANK, PERCENTILE_CONT).Trigger Framework: 7 specialized triggers covering automated JSONB audit trail, salary history tracking, and strict business constraint enforcement.Performance Observability: Live query plan analysis (EXPLAIN ANALYZE), index usage tracking via pg_stat_user_indexes, and cache hit ratio metrics exposed via API endpoints.🏗️ System Architecture┌─────────────────────────────────────────────────────────────┐
│                       WEB DASHBOARD                         │
│             (HTML5 / CSS3 / Chart.js / Dark UI)             │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTP REST API
┌────────────────────────▼────────────────────────────────────┐
│                      FASTAPI BACKEND                        │
│          Python 3.12 · psycopg2 · 20+ Data Endpoints        │
└────────────────────────┬────────────────────────────────────┘
                         │ SQL / PL/pgSQL
┌────────────────────────▼────────────────────────────────────┐
│                       POSTGRESQL 16                         │
│                                                             │
│  ├── Partitioned Tables (employees_2019 ... default)       │
│  ├── Materialized Views (mv_dept_headcount, mv_salary_dist) │
│  ├── Stored Procedures & PL/pgSQL Functions                 │
│  ├── Triggers (Audit, Rules, Salary Log)                    │
│  └── Specialized Indexes (Covering, BRIN, GIN, Partial)     │
└─────────────────────────────────────────────────────────────┘
📁 Repository Structureek-hr-db-intelligence/
├── docker-compose.yml          # Container orchestration
├── database/
│   ├── migrations/
│   │   ├── 01_schema.sql       # DDL, partitioning & constraints
│   │   ├── 02_indexes.sql      # Advanced index definitions
│   │   ├── 03_mviews.sql       # Materialized views
│   │   └── 04_seed_data.sql    # Mock HR dataset
│   ├── procedures/
│   │   └── procedures.sql      # Business logic & analytic functions
│   └── triggers/
│       └── triggers.sql        # Audit & policy enforcement
├── backend/
│   ├── main.py                 # FastAPI routing & database handlers
│   └── requirements.txt
└── frontend/
    ├── index.html              # Monitoring UI
    └── app.js                  # Analytics integration
🚀 Quick SetupRun with DockerBashgit clone git@github.com:emrkacar2/ek-hr-db-intelligence.git
cd ek-hr-db-intelligence
docker-compose up --build
Access the Web Dashboard at http://localhost:8000 or API documentation at http://localhost:8000/docs.Manual Local SetupInitialize Database:Bashcreatedb ek_hr_db
Execute Schema & Scripts:Bashpsql -d ek_hr_db -f database/migrations/01_schema.sql
psql -d ek_hr_db -f database/migrations/02_indexes.sql
psql -d ek_hr_db -f database/migrations/03_mviews.sql
psql -d ek_hr_db -f database/procedures/procedures.sql
psql -d ek_hr_db -f database/triggers/triggers.sql
psql -d ek_hr_db -f database/migrations/04_seed_data.sql
Start Application:Bashcd backend
pip install -r requirements.txt
python main.py
🔍 Technical Implementation Samples1. Covering Index (Index-Only Scan)SQLCREATE INDEX idx_emp_dept_status_covering
    ON employees (department_id, status)
    INCLUDE (first_name, last_name, salary, job_grade)
    WHERE status = 'ACTIVE';
2. Concurrent Materialized View RefreshSQLCREATE UNIQUE INDEX idx_mv_dept_headcount_pk ON mv_dept_headcount(department_id);

-- Executed without locking read operations
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dept_headcount;
3. Dynamic JSONB Audit LoggingSQLCREATE OR REPLACE FUNCTION trg_generic_audit() 
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, operation, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW), CURRENT_USER);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
