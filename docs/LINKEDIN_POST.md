# LinkedIn Post — EK HR DB Intelligence

---

🗄️ Yeni bir veritabanı projesi daha yayında!

Son birkaç haftadır üzerinde çalıştığım **EK HR DB Intelligence**'i GitHub'a pushladım.

PostgreSQL üzerinde, enterprise bir HR sistemi senaryosuyla şu tekniklerin hepsini canlı çalışan bir sistemde uyguladım:

✅ **Range Partitioning** — `employees` tablosu yıllara göre partition'lara bölündü (2019–2025). Tarih bazlı sorgularda partition pruning aktive oluyor, full table scan yok.

✅ **Covering Index** (Index-Only Scan) — `INCLUDE (first_name, last_name, salary)` ile heap fetch tamamen eliminate edildi.

✅ **Partial Index** — `WHERE status = 'ACTIVE'` filtresiyle index boyutu küçültüldü, sadece anlamlı kayıtlar index'lendi.

✅ **BRIN Index** — Zaman serisi `hire_date` kolonu için. B-Tree'nin onda biri boyutunda, range sorgularda mükemmel.

✅ **GIN Index** — JSONB audit sütunları için forensic sorgulama. `new_data @> '{"status":"TERMINATED"}'` gibi sorgular anlık çalışıyor.

✅ **5 Materialized View** — `REFRESH CONCURRENTLY` stratejisi ile sıfır downtime. Department headcount, salary percentile, hiring trend, performance leaderboard, slow query report.

✅ **6 PL/pgSQL Function/Procedure** — Cursor ile bulk salary update, window function'lı analytics report, exception handling, retention cohort analizi.

✅ **7 Trigger** — AFTER UPDATE salary log, JSONB generic audit, BEFORE UPDATE iş kuralı kontrolü (terminate validation, manager grade check), pg_notify ile async MV refresh.

✅ **EXPLAIN ANALYZE Visualizer** — Web dashboard üzerinden canlı execution plan inspection.

Bunların hepsini görebileceğiniz, bağlanıp test edebileceğiniz bir **web dashboard** yaptım. FastAPI backend + Chart.js ile 9 farklı sekme:

— Dashboard (KPI + 4 grafik)
— Employee search
— Department budget cards
— Performance leaderboard (RANK window function)
— Partition details
— Index health report
— EXPLAIN Analyzer
— Audit log (JSONB trigger)
— Table stats (cache hit, vacuum, sizes)

Docker ile tek komutla çalıştırabilirsiniz:
```
docker-compose up --build
```

GitHub repo: [link]

Hayatımda hiç "mükemmel" bir proje yapmadım. Ama her projeyle bir öncekinden daha derine inmek mümkün. Sonraki hedef: Oracle Data Guard veya Streaming Replication senaryosu.

#DatabaseAdministrator #PostgreSQL #Oracle #PLSQL #DBA #SQL #DataEngineering #OpenToWork

---

> 💡 Görseli post'a ekle: docs/dashboard_preview.jpg
