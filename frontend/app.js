/* ═══════════════════════════════════════════════════════════
   EK HR DB Intelligence — Frontend Application Logic
   Author : Emre Kaçar | Database Administrator
   ═══════════════════════════════════════════════════════════ */

const API = 'http://localhost:8000/api';

// ─── Chart.js global defaults ────────────────────────────────
Chart.defaults.color          = '#8a9bbf';
Chart.defaults.font.family    = "'Inter', sans-serif";
Chart.defaults.font.size      = 12;
Chart.defaults.borderColor    = '#1e2d45';
Chart.defaults.plugins.legend.labels.boxWidth = 10;
Chart.defaults.plugins.tooltip.backgroundColor = '#161d2e';
Chart.defaults.plugins.tooltip.borderColor     = '#2a3f5f';
Chart.defaults.plugins.tooltip.borderWidth     = 1;
Chart.defaults.plugins.tooltip.padding         = 10;

const COLORS = {
  blue:   '#3b82f6', green: '#10b981', purple: '#8b5cf6',
  orange: '#f59e0b', cyan:  '#06b6d4', red:    '#ef4444',
  pink:   '#ec4899', teal:  '#14b8a6',
};
const PALETTE = Object.values(COLORS);
const rgba = (hex, a) => {
  const r = parseInt(hex.slice(1,3),16);
  const g = parseInt(hex.slice(3,5),16);
  const b = parseInt(hex.slice(5,7),16);
  return `rgba(${r},${g},${b},${a})`;
};

// ─── State ────────────────────────────────────────────────────
const state = {
  charts: {},
  departments: [],
};

// ─── Utilities ────────────────────────────────────────────────
const fmt = {
  num:  v => v == null ? '—' : Number(v).toLocaleString('en-US'),
  cur:  v => v == null ? '—' : '₺' + Number(v).toLocaleString('en-US', {minimumFractionDigits:0,maximumFractionDigits:0}),
  pct:  v => v == null ? '—' : Number(v).toFixed(1) + '%',
  date: v => v ? new Date(v).toLocaleDateString('en-GB', {day:'2-digit',month:'short',year:'numeric'}) : '—',
  ms:   v => v == null ? '—' : Number(v).toFixed(3) + ' ms',
};

function el(id) { return document.getElementById(id); }

function scoreClass(s) {
  if (s >= 4.5) return 'score-outstanding';
  if (s >= 3.5) return 'score-exceeds';
  if (s >= 2.5) return 'score-meets';
  return 'score-needs';
}

function rankBadge(r) {
  const cls = r === 1 ? 'rank-1' : r === 2 ? 'rank-2' : r === 3 ? 'rank-3' : 'rank-n';
  return `<span class="rank-badge ${cls}">${r}</span>`;
}

async function apiFetch(path) {
  const res = await fetch(API + path);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

function destroyChart(key) {
  if (state.charts[key]) { state.charts[key].destroy(); delete state.charts[key]; }
}

// ─── DB Status ────────────────────────────────────────────────
async function checkDBStatus() {
  try {
    await apiFetch('/overview');
    el('db-status').className = 'db-status connected';
    el('db-status').querySelector('.status-text').textContent = 'PostgreSQL Connected';
  } catch {
    el('db-status').className = 'db-status error';
    el('db-status').querySelector('.status-text').textContent = 'Disconnected';
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB ROUTING
// ═══════════════════════════════════════════════════════════════
const TABS = {
  dashboard:   { title: 'Dashboard',        sub: 'Overview',           load: loadDashboard },
  employees:   { title: 'Employees',         sub: 'HR Management',      load: loadEmployees },
  departments: { title: 'Departments',       sub: 'Budget & Headcount', load: loadDepartments },
  performance: { title: 'Performance',       sub: 'Analytics',          load: loadPerformance },
  partitions:  { title: 'Partitions',        sub: 'DBA Tools',          load: loadPartitions },
  indexes:     { title: 'Index Health',      sub: 'DBA Tools',          load: loadIndexHealth },
  explain:     { title: 'EXPLAIN Analyzer',  sub: 'DBA Tools',          load: loadExplain },
  audit:       { title: 'Audit Log',         sub: 'DBA Tools',          load: loadAuditLog },
  tables:      { title: 'Table Statistics',  sub: 'DBA Tools',          load: loadTableStats },
};

function switchTab(tabKey) {
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));

  const navEl = el('nav-' + tabKey);
  if (navEl) navEl.classList.add('active');

  const tabEl = el('tab-' + tabKey);
  if (tabEl) tabEl.classList.add('active');

  const meta = TABS[tabKey] || {};
  el('page-title').textContent = meta.title || tabKey;
  el('breadcrumb-sub').textContent = meta.sub || tabKey;

  if (meta.load) meta.load();
}

// Navigation click handlers
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', e => {
    e.preventDefault();
    switchTab(item.dataset.tab);
  });
});

// Global refresh
el('btn-global-refresh').addEventListener('click', () => {
  const btn = el('btn-global-refresh');
  btn.classList.add('spinning');
  const active = document.querySelector('.tab-content.active');
  const key = active?.id?.replace('tab-','');
  if (key && TABS[key]) {
    TABS[key].load();
  }
  setTimeout(() => btn.classList.remove('spinning'), 800);
});

// ═══════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════
async function loadDashboard() {
  // KPIs
  try {
    const d = await apiFetch('/overview');
    el('kv-active').textContent = fmt.num(d.active_employees);
    el('kv-payroll').textContent = fmt.cur(d.total_payroll);
    el('kd-payroll').textContent = 'per month total';
    el('kv-avg').textContent = fmt.cur(d.avg_salary);
    el('kv-perf').textContent = d.avg_perf_score ?? '—';
    el('kv-depts').textContent = fmt.num(d.total_departments);
    el('kv-audit').textContent = fmt.num(d.audit_events_24h);
    el('kd-active').textContent = `${fmt.num(d.on_leave)} on leave · ${fmt.num(d.terminated)} terminated`;
    el('kd-avg').textContent = `of ${fmt.num(d.total_employees)} total`;
    el('kd-audit').textContent = 'JSONB trigger captured';
  } catch (e) {
    console.error('KPI load error:', e);
  }

  // Hiring Trend Chart
  try {
    const { data } = await apiFetch('/hiring/trend');
    const months = [...new Set(data.map(r => r.hire_month))].sort().slice(-18);
    const depts  = [...new Set(data.map(r => r.department_name))];

    const datasets = depts.slice(0, 6).map((dept, i) => ({
      label: dept,
      data: months.map(m => {
        const row = data.find(r => r.hire_month === m && r.department_name === dept);
        return row ? row.new_hires : 0;
      }),
      backgroundColor: rgba(PALETTE[i], .7),
      borderColor: PALETTE[i],
      borderWidth: 1,
    }));

    destroyChart('hiring');
    state.charts.hiring = new Chart(el('chartHiring'), {
      type: 'bar',
      data: { labels: months.map(m => m?.substring(0,7)), datasets },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { position: 'top' } },
        scales: {
          x: { stacked: true, grid: { color: 'rgba(30,45,69,.4)' } },
          y: { stacked: true, grid: { color: 'rgba(30,45,69,.4)' }, ticks: { precision: 0 } },
        },
      },
    });
  } catch(e) { console.error('Hiring chart:', e); }

  // Status Donut
  try {
    const d = await apiFetch('/overview');
    destroyChart('status');
    state.charts.status = new Chart(el('chartStatus'), {
      type: 'doughnut',
      data: {
        labels: ['Active', 'On Leave', 'Terminated'],
        datasets: [{
          data: [d.active_employees, d.on_leave, d.terminated],
          backgroundColor: [rgba(COLORS.green,.8), rgba(COLORS.orange,.8), rgba(COLORS.red,.8)],
          borderColor:     [COLORS.green, COLORS.orange, COLORS.red],
          borderWidth: 1.5,
          hoverOffset: 6,
        }],
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        cutout: '68%',
        plugins: { legend: { position: 'bottom' } },
      },
    });
  } catch(e) { console.error('Status chart:', e); }

  // Salary Distribution
  try {
    const { data } = await apiFetch('/salary/distribution');
    destroyChart('salary');
    state.charts.salary = new Chart(el('chartSalary'), {
      type: 'bar',
      data: {
        labels: data.map(r => r.grade_code + ' — ' + r.title),
        datasets: [
          {
            label: 'Min Salary',
            data: data.map(r => r.min_salary),
            backgroundColor: rgba(COLORS.blue,.3),
            borderColor: COLORS.blue, borderWidth: 1,
          },
          {
            label: 'P50 Salary',
            data: data.map(r => r.p50_salary),
            backgroundColor: rgba(COLORS.cyan,.5),
            borderColor: COLORS.cyan, borderWidth: 1,
          },
          {
            label: 'Max Salary',
            data: data.map(r => r.max_salary),
            backgroundColor: rgba(COLORS.purple,.3),
            borderColor: COLORS.purple, borderWidth: 1,
          },
        ],
      },
      options: {
        responsive: true, maintainAspectRatio: false, indexAxis: 'y',
        plugins: { legend: { position: 'top' } },
        scales: {
          x: { grid: { color: 'rgba(30,45,69,.4)' } },
          y: { grid: { display: false } },
        },
      },
    });
  } catch(e) { console.error('Salary chart:', e); }

  // Payroll by Department
  try {
    const { data } = await apiFetch('/departments');
    destroyChart('payroll');
    state.charts.payroll = new Chart(el('chartPayroll'), {
      type: 'bar',
      data: {
        labels: data.map(r => r.department_name),
        datasets: [{
          label: 'Total Payroll (₺)',
          data: data.map(r => r.total_payroll || 0),
          backgroundColor: data.map((_, i) => rgba(PALETTE[i % PALETTE.length], .7)),
          borderColor:     data.map((_, i) => PALETTE[i % PALETTE.length]),
          borderWidth: 1.5, borderRadius: 4,
        }],
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          x: { grid: { display: false } },
          y: { grid: { color: 'rgba(30,45,69,.4)' } },
        },
      },
    });
  } catch(e) { console.error('Payroll chart:', e); }
}

// ═══════════════════════════════════════════════════════════════
// EMPLOYEES
// ═══════════════════════════════════════════════════════════════
async function loadEmployees() {
  // Populate dept filter
  try {
    if (state.departments.length === 0) {
      const { data } = await apiFetch('/departments');
      state.departments = data;
      const sel = el('emp-dept-filter');
      data.forEach(d => {
        const opt = document.createElement('option');
        opt.value = d.department_id;
        opt.textContent = d.department_name;
        sel.appendChild(opt);
      });
    }
  } catch {}
  await searchEmployees();
}

async function searchEmployees() {
  const search  = el('emp-search').value;
  const deptId  = el('emp-dept-filter').value;
  const status  = el('emp-status-filter').value;
  let url = '/employees?limit=100';
  if (search)  url += '&search=' + encodeURIComponent(search);
  if (deptId)  url += '&department_id=' + deptId;
  if (status)  url += '&status=' + status;

  try {
    const { data, count, query_exec_ms } = await apiFetch(url);
    el('emp-table-meta').textContent =
      `${fmt.num(count)} employees · query: ${fmt.ms(query_exec_ms)}`;

    const tbody = el('emp-tbody');
    tbody.innerHTML = data.map(e => `
      <tr>
        <td class="mono">#${e.employee_id}</td>
        <td style="font-weight:600;color:var(--text-primary)">${e.first_name} ${e.last_name}</td>
        <td style="color:var(--text-muted);font-size:12px">${e.email}</td>
        <td>${e.department_name}</td>
        <td><span class="mono" style="color:var(--accent-cyan)">${e.job_grade}</span> · ${e.job_title}</td>
        <td style="color:var(--accent-green);font-weight:600">${fmt.cur(e.salary)}</td>
        <td><span class="badge badge-${(e.status||'').toLowerCase()}">${e.status}</span></td>
        <td class="mono" style="font-size:12px">${fmt.date(e.hire_date)}</td>
        <td style="color:var(--text-muted)">${e.yrs_of_service ?? '—'} yrs</td>
      </tr>
    `).join('');
  } catch(err) {
    el('emp-tbody').innerHTML = `<tr><td colspan="9" style="color:var(--accent-red);text-align:center">Error: ${err.message}</td></tr>`;
  }
}

el('btn-emp-search').addEventListener('click', searchEmployees);
el('emp-search').addEventListener('keydown', e => { if (e.key === 'Enter') searchEmployees(); });

// ═══════════════════════════════════════════════════════════════
// DEPARTMENTS
// ═══════════════════════════════════════════════════════════════
async function loadDepartments() {
  try {
    const { data } = await apiFetch('/departments');
    state.departments = data;
    const grid = el('dept-grid');
    grid.innerHTML = data.map(d => {
      const pct = d.budget_utilization_pct || 0;
      const warning = pct > 85;
      return `
        <div class="dept-card">
          <div class="dept-card-header">
            <div>
              <div class="dept-name">${d.department_name}</div>
              <div class="dept-location">📍 ${d.location || '—'}</div>
            </div>
            <span class="badge ${warning ? 'badge-terminated' : 'badge-active'}">${fmt.pct(pct)}</span>
          </div>
          <div class="dept-stats">
            <div class="dept-stat-row">
              <span class="dept-stat-label">Active Employees</span>
              <span class="dept-stat-value">${fmt.num(d.active_employees)}</span>
            </div>
            <div class="dept-stat-row">
              <span class="dept-stat-label">Total Payroll</span>
              <span class="dept-stat-value">${fmt.cur(d.total_payroll)}</span>
            </div>
            <div class="dept-stat-row">
              <span class="dept-stat-label">Avg Salary</span>
              <span class="dept-stat-value">${fmt.cur(d.avg_active_salary)}</span>
            </div>
            <div class="dept-stat-row">
              <span class="dept-stat-label">Budget</span>
              <span class="dept-stat-value">${fmt.cur(d.budget)}</span>
            </div>
            <div class="dept-stat-row">
              <span class="dept-stat-label">Remaining</span>
              <span class="dept-stat-value" style="color:${warning?'var(--accent-red)':'var(--accent-green)'}">${fmt.cur(d.budget_remaining)}</span>
            </div>
          </div>
          <div class="budget-bar">
            <div class="budget-bar-fill ${warning?'warning':''}" style="width:${Math.min(pct,100)}%"></div>
          </div>
        </div>
      `;
    }).join('');
  } catch(err) {
    el('dept-grid').innerHTML = `<p style="color:var(--accent-red)">Error: ${err.message}</p>`;
  }
}

// ═══════════════════════════════════════════════════════════════
// PERFORMANCE
// ═══════════════════════════════════════════════════════════════
async function loadPerformance() {
  // Leaderboard chart
  try {
    const { data } = await apiFetch('/performance/leaderboard?limit=15');
    destroyChart('leaderboard');
    state.charts.leaderboard = new Chart(el('chartLeaderboard'), {
      type: 'bar',
      data: {
        labels: data.map(r => r.full_name),
        datasets: [{
          label: 'Avg Score',
          data: data.map(r => r.avg_score),
          backgroundColor: data.map(r => rgba(r.avg_score >= 4.5 ? COLORS.green : r.avg_score >= 3.5 ? COLORS.cyan : COLORS.orange, .7)),
          borderColor: data.map(r => r.avg_score >= 4.5 ? COLORS.green : r.avg_score >= 3.5 ? COLORS.cyan : COLORS.orange),
          borderWidth: 1.5, borderRadius: 4,
        }],
      },
      options: {
        responsive: true, maintainAspectRatio: false, indexAxis: 'y',
        plugins: { legend: { display: false } },
        scales: {
          x: { min: 0, max: 5, grid: { color: 'rgba(30,45,69,.4)' } },
          y: { grid: { display: false } },
        },
      },
    });

    // Table
    el('perf-tbody').innerHTML = data.map(r => `
      <tr>
        <td>${rankBadge(r.overall_rank)}</td>
        <td style="font-weight:600;color:var(--text-primary)">${r.full_name}</td>
        <td>${r.department_name}</td>
        <td style="font-size:12px;color:var(--text-muted)">${r.job_title}</td>
        <td class="${scoreClass(r.avg_score)}" style="font-weight:700">${r.avg_score}</td>
        <td><span class="badge badge-active" style="font-size:10px">${r.avg_score >= 4.5 ? '⭐ Outstanding' : r.avg_score >= 3.5 ? '✅ Exceeds' : '📊 Meets'}</span></td>
        <td class="mono">${r.review_count}</td>
        <td class="mono" style="color:var(--text-muted)">#${r.dept_rank}</td>
      </tr>
    `).join('');
  } catch(e) { console.error('Leaderboard:', e); }

  // Retention chart
  try {
    const { data } = await apiFetch('/performance/retention?year=2023');
    destroyChart('retention');
    state.charts.retention = new Chart(el('chartRetention'), {
      type: 'line',
      data: {
        labels: data.map(r => r.cohort_month?.substring(0,7) || ''),
        datasets: [{
          label: 'Retention %',
          data: data.map(r => r.retention_rate_pct),
          borderColor: COLORS.green,
          backgroundColor: rgba(COLORS.green, .1),
          fill: true,
          tension: .4,
          pointBackgroundColor: COLORS.green,
          pointRadius: 4,
        }],
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          y: { min: 0, max: 100, grid: { color: 'rgba(30,45,69,.4)' }, ticks: { callback: v => v+'%' } },
          x: { grid: { display: false } },
        },
      },
    });
  } catch(e) { console.error('Retention:', e); }
}

// ═══════════════════════════════════════════════════════════════
// PARTITIONS
// ═══════════════════════════════════════════════════════════════
async function loadPartitions() {
  try {
    const { data } = await apiFetch('/dba/partition-info');
    el('part-tbody').innerHTML = data.map(r => `
      <tr class="${r.parent_table === 'employees' ? 'part-employees' : 'part-salary'}">
        <td style="font-family:'JetBrains Mono',monospace;color:${r.parent_table==='employees'?'var(--accent-blue)':'var(--accent-purple)'}">${r.parent_table}</td>
        <td style="font-family:'JetBrains Mono',monospace;font-size:12px">${r.partition_name}</td>
        <td style="font-size:12px;color:var(--text-secondary)">${r.partition_range || '—'}</td>
        <td class="mono">${fmt.num(r.live_rows)}</td>
        <td style="color:var(--accent-cyan)">${r.partition_size}</td>
      </tr>
    `).join('');
  } catch(e) {
    el('part-tbody').innerHTML = `<tr><td colspan="5" style="color:var(--accent-red);text-align:center">Start the backend: cd backend && python main.py</td></tr>`;
  }
}

// ═══════════════════════════════════════════════════════════════
// INDEX HEALTH
// ═══════════════════════════════════════════════════════════════
async function loadIndexHealth() {
  try {
    const { data } = await apiFetch('/dba/index-health');
    el('idx-tbody').innerHTML = data.map(r => `
      <tr>
        <td class="mono" style="color:var(--accent-cyan)">${r.table_name}</td>
        <td class="mono" style="font-size:11.5px">${r.index_name}</td>
        <td style="color:var(--accent-orange)">${r.index_size}</td>
        <td class="mono">${fmt.num(r.idx_scan)}</td>
        <td class="mono">${fmt.num(r.idx_tup_read)}</td>
        <td style="font-size:12px">${r.usage_rating}</td>
      </tr>
    `).join('');
  } catch(e) {
    el('idx-tbody').innerHTML = `<tr><td colspan="6" style="color:var(--accent-orange);text-align:center">⚡ Indexes are defined — start the backend to see live pg_stat data</td></tr>`;
  }
}

// ═══════════════════════════════════════════════════════════════
// EXPLAIN ANALYZER
// ═══════════════════════════════════════════════════════════════
async function loadExplain() {
  try {
    const { keys } = await apiFetch('/dba/explain-keys');
    const container = el('explain-buttons');
    container.innerHTML = keys.map(k => `
      <button class="explain-btn" data-key="${k}" onclick="runExplain('${k}')">
        ▶ ${k.replace(/_/g,' ')}
      </button>
    `).join('');
  } catch {
    el('explain-buttons').innerHTML = '<p style="color:var(--text-muted)">Start backend to use EXPLAIN Analyzer</p>';
  }
}

async function runExplain(key) {
  document.querySelectorAll('.explain-btn').forEach(b => b.classList.remove('loading'));
  const btn = document.querySelector(`.explain-btn[data-key="${key}"]`);
  if (btn) btn.classList.add('loading');

  el('explain-result').classList.remove('hidden');
  el('explain-sql-text').textContent = 'Running EXPLAIN ANALYZE...';
  el('explain-plan-text').textContent = '';
  el('explain-stats').innerHTML = '';

  try {
    const d = await apiFetch('/dba/explain/' + key);
    el('explain-sql-text').textContent = d.sql;

    // Extract plan stats
    const plan = Array.isArray(d.plan) ? d.plan[0] : d.plan;
    const node = plan?.Plan || {};

    el('explain-stats').innerHTML = [
      { label: 'Execution Time',  value: fmt.ms(plan?.['Execution Time']) },
      { label: 'Planning Time',   value: fmt.ms(plan?.['Planning Time']) },
      { label: 'Node Type',       value: node['Node Type'] || '—' },
      { label: 'Actual Rows',     value: fmt.num(node['Actual Rows']) },
      { label: 'Actual Loops',    value: fmt.num(node['Actual Loops']) },
      { label: 'Total Cost',      value: node['Total Cost'] ?? '—' },
    ].map(s => `
      <div class="explain-stat">
        <div class="explain-stat-value">${s.value}</div>
        <div class="explain-stat-label">${s.label}</div>
      </div>
    `).join('');

    el('explain-plan-text').textContent = JSON.stringify(d.plan, null, 2);
  } catch(err) {
    el('explain-sql-text').textContent = `Error: ${err.message}\n\nMake sure the backend is running on localhost:8000`;
    el('explain-plan-text').textContent = '';
  } finally {
    if (btn) btn.classList.remove('loading');
  }
}

// Make runExplain global
window.runExplain = runExplain;

// ═══════════════════════════════════════════════════════════════
// AUDIT LOG
// ═══════════════════════════════════════════════════════════════
async function loadAuditLog() {
  try {
    const { data, query_exec_ms } = await apiFetch('/dba/audit-log?limit=80');
    el('audit-tbody').innerHTML = data.map(r => {
      const changes = r.new_data
        ? Object.keys(r.new_data).slice(0,3).map(k =>
            `<code style="font-size:10px;background:rgba(59,130,246,.08);color:#7dd3fc;padding:1px 4px;border-radius:2px">${k}</code>`
          ).join(' ')
        : '—';
      return `
        <tr>
          <td class="mono">${r.audit_id}</td>
          <td class="mono" style="color:var(--accent-cyan)">${r.table_name}</td>
          <td><span class="badge badge-${r.operation.toLowerCase()}">${r.operation}</span></td>
          <td class="mono">${r.record_id || '—'}</td>
          <td style="color:var(--text-secondary)">${r.changed_by}</td>
          <td class="mono" style="font-size:11px">${fmt.date(r.changed_at)}</td>
          <td>${changes}</td>
        </tr>
      `;
    }).join('');
  } catch(e) {
    el('audit-tbody').innerHTML = `<tr><td colspan="7" style="color:var(--accent-orange);text-align:center">🔒 Audit log captures all DML changes via AFTER triggers — start backend to view</td></tr>`;
  }
}

// ═══════════════════════════════════════════════════════════════
// TABLE STATS
// ═══════════════════════════════════════════════════════════════
async function loadTableStats() {
  try {
    const [tsRes, cacheRes] = await Promise.all([
      apiFetch('/dba/table-stats'),
      apiFetch('/dba/cache-hit'),
    ]);

    // Table list
    el('ts-tbody').innerHTML = tsRes.data.map(r => `
      <tr>
        <td class="mono" style="color:var(--accent-cyan)">${r.tablename}</td>
        <td style="color:var(--accent-orange)">${r.total_size}</td>
        <td>${r.table_size}</td>
        <td style="color:var(--accent-purple)">${r.index_size}</td>
        <td class="mono">${fmt.num(r.live_rows)}</td>
        <td class="mono" style="color:${r.dead_rows>1000?'var(--accent-red)':'var(--text-muted)'}">${fmt.num(r.dead_rows)}</td>
        <td class="mono" style="font-size:11px">${fmt.date(r.last_autovacuum || r.last_vacuum)}</td>
      </tr>
    `).join('');

    // Cache Hit Chart
    const cacheData = cacheRes.data.filter(r => r.cache_hit_pct != null).slice(0,8);
    destroyChart('cache');
    state.charts.cache = new Chart(el('chartCache'), {
      type: 'bar',
      data: {
        labels: cacheData.map(r => r.relname),
        datasets: [{
          label: 'Cache Hit %',
          data: cacheData.map(r => r.cache_hit_pct),
          backgroundColor: cacheData.map(r => rgba(r.cache_hit_pct >= 95 ? COLORS.green : r.cache_hit_pct >= 80 ? COLORS.orange : COLORS.red, .7)),
          borderColor:     cacheData.map(r => r.cache_hit_pct >= 95 ? COLORS.green : r.cache_hit_pct >= 80 ? COLORS.orange : COLORS.red),
          borderWidth: 1.5, borderRadius: 4,
        }],
      },
      options: {
        responsive: true, maintainAspectRatio: false, indexAxis: 'y',
        plugins: { legend: { display: false } },
        scales: {
          x: { min: 0, max: 100, grid: { color: 'rgba(30,45,69,.4)' }, ticks: { callback: v => v+'%' } },
          y: { grid: { display: false } },
        },
      },
    });

    // Table Size Chart
    const sizeData = tsRes.data.slice(0,8);
    destroyChart('tablesize');
    state.charts.tablesize = new Chart(el('chartTableSize'), {
      type: 'bar',
      data: {
        labels: sizeData.map(r => r.tablename),
        datasets: [
          {
            label: 'Live Rows',
            data: sizeData.map(r => r.live_rows || 0),
            backgroundColor: rgba(COLORS.blue, .6),
            borderColor: COLORS.blue, borderWidth: 1.5, borderRadius: 4,
          },
        ],
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          x: { grid: { display: false } },
          y: { grid: { color: 'rgba(30,45,69,.4)' }, ticks: { precision: 0 } },
        },
      },
    });

  } catch(e) {
    console.error('Table stats:', e);
    el('ts-tbody').innerHTML = `<tr><td colspan="7" style="color:var(--accent-orange);text-align:center">Start the backend to view pg_stat_user_tables data</td></tr>`;
  }
}

// ═══════════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════════
async function init() {
  await checkDBStatus();
  switchTab('dashboard');
}

init();
