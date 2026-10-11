# perfq.py (perfmon-triage v2.1) - query helpers for a PerfMon capture converted to SQLite by perfmon_csv_to_sqlite.py
# (tables meta, samples, counters, vals; view perf).
# Python standard library only. Load with:  exec(open(PERFQ).read()); db = open_db(DB)
# Every helper prints aggregates, never raw data rows, and caps its output (MAX_ROWS rows, MAX_POINTS points).
import sqlite3, math

MAX_ROWS = 20
MAX_POINTS = 30
EXCL = ('_Total', 'Idle', '__Total__', '_Global_')


def open_db(path):
    con = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    return con


def _f(v):
    if isinstance(v, float):
        if v.is_integer() and abs(v) < 1e15:
            return f'{int(v):,}'
        if v != 0 and abs(v) < 1e-3:
            return f'{v:.3e}'
        return f'{v:,.4f}' if abs(v) < 10 else f'{v:,.1f}'
    if isinstance(v, int):
        return f'{v:,}'
    return '' if v is None else str(v)[:48]


def _print(cols, rows, limit):
    print(' | '.join(cols))
    for r in rows[:limit]:
        print(' | '.join(_f(v) for v in r))
    if len(rows) > limit:
        print(f'... ({len(rows) - limit} more rows cut)')


def show(con, sql, params=(), limit=MAX_ROWS):
    """Run any aggregate query; prints at most `limit` rows."""
    cur = con.execute(sql, params)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchmany(limit + 1)
    _print(cols, rows, limit)
    return rows


def ids(con, obj, counter, instance=None):
    sql = 'SELECT counter_id FROM counters WHERE object LIKE ? AND counter LIKE ?'
    p = [obj, counter]
    if instance is not None:
        sql += " AND coalesce(instance,'') LIKE ?"
        p.append(instance)
    return [r[0] for r in con.execute(sql, p)]


def interval_s(con):
    return float(con.execute("SELECT value FROM meta WHERE key='sample_interval_s'").fetchone()[0])


def cpu_object(con):
    """'Processor' if the capture has it, else 'Processor Information' (same counters; instances '_Total',
    '0,_Total' per NUMA node, '0,0' per core)."""
    r = con.execute("SELECT 1 FROM counters WHERE object='Processor' AND counter='% Processor Time' LIMIT 1").fetchone()
    return 'Processor' if r else 'Processor Information'


def _is_total(instance):
    return instance is None or instance.endswith('_Total')


def n_cpu(con):
    """Logical CPUs: per-core instances of % Processor Time (Processor, or Processor Information without the
    '_Total' and '<node>,_Total' instances)."""
    rows = con.execute("SELECT instance FROM counters WHERE object=? AND counter='% Processor Time'",
                       (cpu_object(con),)).fetchall()
    return sum(1 for (i,) in rows if not _is_total(i))


def _vals(con, cid, start=None, end=None):
    return con.execute('SELECT s.sample_id, s.ts, v.value FROM vals v JOIN samples s USING(sample_id) '
                       'WHERE v.counter_id=? AND s.ts >= coalesce(?, s.ts) AND s.ts <= coalesce(?, s.ts) '
                       'ORDER BY s.sample_id', (cid, start, end)).fetchall()


def _breach(vals, op, thr, iv):
    bad = (lambda v: v > thr) if op == '>' else (lambda v: v < thr)
    n_bad = run = best = 0
    start = best_start = None
    prev = None
    for sid, ts, v in vals:
        if bad(v):
            n_bad += 1
            if run == 0 or prev != sid - 1:
                run, start = 0, ts
            run += 1
            if run > best:
                best, best_start = run, start
        else:
            run = 0
        prev = sid
    return n_bad, best * iv / 60.0, best_start


def is_cumulative(con, cid):
    """True if the counter never decreases over the capture: a running total, not a rate. Use its delta."""
    r = con.execute('''SELECT count(*), sum(CASE WHEN d < 0 THEN 1 ELSE 0 END), sum(CASE WHEN d > 0 THEN 1 ELSE 0 END)
        FROM (SELECT value - lag(value) OVER (ORDER BY sample_id) d FROM vals WHERE counter_id=?)''', (cid,)).fetchone()
    return r[0] > 10 and (r[1] or 0) == 0 and (r[2] or 0) > 0


def check(con, obj, counter, instance, op, threshold, label=None, limit=8, start=None, end=None):
    """Per matching instance: avg, p95, max, min, % samples breaching, longest continuous breach (minutes) and
    when it started. op is '>' or '<'. Returns rows sorted worst first."""
    cids = ids(con, obj, counter, instance)
    name = label or f'{obj}\\{counter}'
    if not cids:
        print(f'-- {name}: not in capture')
        return []
    iv = interval_s(con)
    out = []
    for cid in cids:
        vals = _vals(con, cid, start, end)
        if not vals:
            continue
        xs = sorted(v for _, _, v in vals)
        n_bad, longest, longest_from = _breach(vals, op, threshold, iv)
        inst = con.execute('SELECT instance FROM counters WHERE counter_id=?', (cid,)).fetchone()[0]
        out.append((inst or '', sum(xs) / len(xs), xs[int(0.95 * (len(xs) - 1))], xs[-1], xs[0],
                    100.0 * n_bad / len(xs), longest, longest_from or ''))
    out.sort(key=lambda r: (-r[6], -r[5], -r[3]))
    print(f'-- {name}  breach {op} {threshold}')
    _print(['instance', 'avg', 'p95', 'max', 'min', '%breach', 'longest_min', 'longest_from'], out, limit)
    return out


def _bucket(sec):
    return f"datetime((CAST(strftime('%s', s.ts) AS INTEGER) / {sec}) * {sec}, 'unixepoch')"


def series(con, obj, counter, instance=None, start=None, end=None, bucket_min=None, max_points=MAX_POINTS):
    """One counter over time, bucketed so it prints at most max_points rows: avg, min, max per bucket, and the
    exact sample time of each bucket's peak (peak_at) and low (low_at). Quote those times, never the bucket label."""
    cids = ids(con, obj, counter, instance)
    if len(cids) != 1:
        print(f'-- series needs exactly one counter, matched {len(cids)}; narrow the instance pattern')
        return
    t0, t1 = con.execute('SELECT min(ts), max(ts) FROM samples WHERE ts >= coalesce(?, ts) AND ts <= coalesce(?, ts)',
                         (start, end)).fetchone()
    span = con.execute('SELECT (julianday(?) - julianday(?)) * 1440', (t1, t0)).fetchone()[0]
    if bucket_min is None:
        bucket_min = max(1, math.ceil(span / (max_points - 1)))
    sec = int(bucket_min * 60)
    print(f'-- {obj}\\{counter} [{instance or ""}] {t0} .. {t1}, bucket {bucket_min} min')
    show(con, f'''WITH b AS (SELECT {_bucket(sec)} AS bucket, s.ts, v.value,
                         row_number() OVER (PARTITION BY {_bucket(sec)} ORDER BY v.value DESC, s.ts) rn_hi,
                         row_number() OVER (PARTITION BY {_bucket(sec)} ORDER BY v.value ASC, s.ts) rn_lo
                  FROM vals v JOIN samples s USING(sample_id)
                  WHERE v.counter_id = ? AND s.ts BETWEEN ? AND ?)
                  SELECT bucket, avg(value) avg_v, min(value) min_v, max(value) max_v,
                         max(CASE WHEN rn_hi = 1 THEN substr(ts, 1, 19) END) peak_at,
                         max(CASE WHEN rn_lo = 1 THEN substr(ts, 1, 19) END) low_at
                  FROM b GROUP BY bucket ORDER BY bucket''',
         (cids[0], t0, t1), limit=max_points)


def movers(con, obj='Process', counters=('Private Bytes', 'Working Set', 'Handle Count', 'Thread Count'),
           top=8, start=None, end=None):
    """Instances whose value grew most: least-squares slope per hour, plus first/last/max. Run per counter.
    An instance name such as 'w3wp' can point to different processes over time; check 'ID Process'."""
    for ctr in counters:
        rows = con.execute(f'''
            WITH s AS (SELECT sample_id, (julianday(ts) - julianday((SELECT min(ts) FROM samples))) * 24 AS x
                       FROM samples WHERE ts >= coalesce(?, ts) AND ts <= coalesce(?, ts))
            SELECT c.instance, count(*) n,
                   (count(*) * sum(x * v.value) - sum(x) * sum(v.value)) / nullif(count(*) * sum(x * x) - sum(x) * sum(x), 0) slope_per_h,
                   min(v.value) mn, max(v.value) mx
            FROM s JOIN vals v USING(sample_id) JOIN counters c USING(counter_id)
            WHERE c.object = ? AND c.counter = ? AND coalesce(c.instance,'') NOT IN ({','.join('?' * len(EXCL))})
            GROUP BY c.counter_id HAVING n > 30 ORDER BY slope_per_h DESC LIMIT ?''',
            (start, end, obj, ctr, *EXCL, top)).fetchall()
        print(f'-- movers {obj}\\{ctr} (top {top} by slope/hour; n = samples present)')
        _print(['instance', 'n', 'slope_per_h', 'min', 'max'], rows, top)


def top_procs(con, counter='% Processor Time', top=10, start=None, end=None):
    """Top processes for one counter. avg_whole = sum / samples in the window (a process absent most of the time
    scores low); avg_present = average while it existed; present_min = how long it existed. Per-core units for CPU."""
    n = con.execute('SELECT count(*) FROM samples WHERE ts >= coalesce(?, ts) AND ts <= coalesce(?, ts)',
                    (start, end)).fetchone()[0]
    iv = interval_s(con)
    return show(con, f'''SELECT c.instance, sum(v.value) / ? avg_whole, avg(v.value) avg_present, max(v.value) max_v,
               count(*) * ? / 60.0 present_min
        FROM vals v JOIN counters c USING(counter_id) JOIN samples s USING(sample_id)
        WHERE c.object = 'Process' AND c.counter = ? AND s.ts >= coalesce(?, s.ts) AND s.ts <= coalesce(?, s.ts)
          AND coalesce(c.instance,'') NOT IN ({','.join('?' * len(EXCL))})
        GROUP BY c.counter_id ORDER BY avg_whole DESC''', (n, iv, counter, start, end, *EXCL), limit=top)


def top_at(con, obj, counter, ts_from, ts_to, top=10):
    """Top instances by average of one counter inside a time window."""
    return show(con, f'''SELECT c.instance, avg(v.value) avg_v, max(v.value) max_v, count(*) n
        FROM vals v JOIN counters c USING(counter_id) JOIN samples s USING(sample_id)
        WHERE c.object LIKE ? AND c.counter LIKE ? AND s.ts BETWEEN ? AND ?
          AND coalesce(c.instance,'') NOT IN ({','.join('?' * len(EXCL))})
        GROUP BY c.counter_id ORDER BY avg_v DESC''', (obj, counter, ts_from, ts_to, *EXCL), limit=top)


def delta(con, obj, counter, ts_from, ts_to, top=10):
    """Change between the first and the last sample of a window, per instance: what moved before an event."""
    return show(con, f'''WITH w AS (
            SELECT c.counter_id, c.instance, v.value,
                   row_number() OVER (PARTITION BY c.counter_id ORDER BY s.sample_id) rn_first,
                   row_number() OVER (PARTITION BY c.counter_id ORDER BY s.sample_id DESC) rn_last
            FROM vals v JOIN counters c USING(counter_id) JOIN samples s USING(sample_id)
            WHERE c.object LIKE ? AND c.counter LIKE ? AND s.ts BETWEEN ? AND ?
              AND coalesce(c.instance,'') NOT IN ({','.join('?' * len(EXCL))}))
        SELECT instance, max(CASE WHEN rn_first=1 THEN value END) first_v, max(CASE WHEN rn_last=1 THEN value END) last_v,
               max(CASE WHEN rn_last=1 THEN value END) - max(CASE WHEN rn_first=1 THEN value END) change
        FROM w GROUP BY counter_id ORDER BY abs(change) DESC''', (obj, counter, ts_from, ts_to, *EXCL), limit=top)


def events(con, obj, counter, instance, op, threshold, limit=10):
    """Contiguous breach episodes of one counter: start, end, duration (min), worst value. Short list, worst first."""
    cids = ids(con, obj, counter, instance)
    if len(cids) != 1:
        print(f'-- events needs exactly one counter, matched {len(cids)}')
        return []
    iv = interval_s(con)
    bad = (lambda v: v > threshold) if op == '>' else (lambda v: v < threshold)
    eps, cur, last_bad = [], None, None
    for sid, ts, v in _vals(con, cids[0]):
        if bad(v):
            if cur and last_bad == sid - 1:
                cur[1], cur[2] = ts, cur[2] + 1
                cur[3] = max(cur[3], v) if op == '>' else min(cur[3], v)
            else:
                cur = [ts, ts, 1, v]
                eps.append(cur)
            last_bad = sid
    rows = sorted(((a, b, n * iv / 60.0, w) for a, b, n, w in eps), key=lambda r: -r[2])
    print(f'-- episodes {obj}\\{counter} [{instance or ""}] {op} {threshold}: {len(rows)} episodes')
    _print(['start', 'end', 'minutes', 'worst'], rows, limit)
    return rows


def pid_changes(con, base_instance, limit=10):
    """When the process behind an instance name changed (restart, recycle, re-numbering)."""
    return show(con, '''SELECT c.instance, s.ts, v.value pid FROM vals v JOIN samples s USING(sample_id)
        JOIN counters c USING(counter_id)
        WHERE c.object='Process' AND c.counter='ID Process' AND c.base_instance = ?
          AND v.value <> coalesce((SELECT v2.value FROM vals v2 WHERE v2.counter_id = v.counter_id
                                   AND v2.sample_id = v.sample_id - 1), -1)
        ORDER BY s.ts''', (base_instance,), limit=limit)


# Fixed breadth checklist: (area, object, counter, instance, op, threshold-or-callable(N), why)
CHECKLIST = [
    ('CPU', 'Processor', '% Processor Time', '_Total', '>', 85, 'machine CPU saturated'),
    ('CPU', 'Processor', '% Processor Time', '%', '>', 95, 'one core pegged'),
    ('CPU', 'Processor', '% Privileged Time', '_Total', '>', 30, 'kernel time high'),
    ('CPU', 'Processor', '% DPC Time', '_Total', '>', 10, 'driver DPC storm'),
    ('CPU', 'Processor', '% Interrupt Time', '_Total', '>', 10, 'interrupt storm'),
    ('CPU', 'System', 'Processor Queue Length', None, '>', lambda n: 2 * n, 'threads waiting for CPU'),
    ('CPU', 'System', 'Context Switches/sec', None, '>', lambda n: 20000 * n, 'context-switch thrash'),
    ('Memory', 'Memory', 'Available MBytes', None, '<', 'avail', 'little RAM left (5 % of RAM, or 500 MB)'),
    ('Memory', 'Memory', '% Committed Bytes In Use', None, '>', 90, 'commit near limit'),
    ('Memory', 'Memory', 'Pages Input/sec', None, '>', 100, 'hard faults'),
    ('Memory', 'Memory', 'Free System Page Table Entries', None, '<', 5000, 'kernel PTEs exhausted'),
    ('Memory', 'Paging File', '% Usage', '_Total', '>', 70, 'paging file filling'),
    ('Disk', 'PhysicalDisk', 'Avg. Disk sec/Read', '%', '>', 0.025, 'slow reads'),
    ('Disk', 'PhysicalDisk', 'Avg. Disk sec/Write', '%', '>', 0.025, 'slow writes'),
    ('Disk', 'LogicalDisk', 'Avg. Disk sec/Read', '%', '>', 0.025, 'slow reads'),
    ('Disk', 'LogicalDisk', 'Avg. Disk sec/Write', '%', '>', 0.025, 'slow writes'),
    ('Disk', 'PhysicalDisk', 'Current Disk Queue Length', '%', '>', 2, 'I/O backlog'),
    ('Disk', 'PhysicalDisk', '% Idle Time', '%', '<', 10, 'disk saturated'),
    ('Disk', 'LogicalDisk', '% Idle Time', '%', '<', 10, 'disk saturated'),
    ('Disk', 'LogicalDisk', '% Free Space', '%', '<', 10, 'disk nearly full'),
    ('Network', 'Network Interface', 'Output Queue Length', '%', '>', 2, 'NIC send backlog'),
    ('App', 'ASP.NET%', 'Requests Queued', '%', '>', 5, 'ASP.NET queueing'),
    ('App', 'ASP.NET Applications', 'Requests In Application Queue', '%', '>', 5, 'app queueing'),
    ('App', 'HTTP Service Request Queues', 'CurrentQueueSize', '%', '>', 5, 'HTTP.sys queueing'),
    ('App', '.NET CLR Memory', '% Time in GC', '%', '>', 20, 'GC pressure'),
]


def triage(con, min_minutes=5):
    """Run CHECKLIST once. Prints one line per check: worst instance, worst value, % samples breaching, longest
    continuous breach. A check matters for usability only if its longest breach >= min_minutes."""
    n = n_cpu(con)
    cpu_obj = cpu_object(con)
    avail_thr = 500
    r = con.execute("SELECT max_value FROM counters WHERE object='Memory' AND counter='Available MBytes'").fetchone()
    print(f'logical CPUs: {n} (from {cpu_obj}); Available MBytes max seen: {r[0] if r else "n/a"} '
          '(RAM is not a counter; estimate it)')
    lines = []
    for area, obj, ctr, inst, op, thr, why in CHECKLIST:
        if obj == 'Processor':
            obj = cpu_obj
        if thr == 'avail':
            thr = avail_thr
        elif callable(thr):
            if not n:
                lines.append((area, f'{obj}\\{ctr}', '-', None, None, None, None, None,
                              'not checked: CPU count unknown (no per-core processor counter)'))
                continue
            thr = thr(n)
        cids = ids(con, obj, ctr, inst)
        if not cids:
            lines.append((area, f'{obj}\\{ctr}', '-', None, None, None, None, None, 'not in capture'))
            continue
        iv = interval_s(con)
        worst = None
        for cid in cids:
            inst_name = con.execute('SELECT coalesce(instance,\'\') FROM counters WHERE counter_id=?', (cid,)).fetchone()[0]
            if inst == '%' and (inst_name in EXCL or (obj == 'Processor Information' and _is_total(inst_name))):
                continue
            vals = _vals(con, cid)
            if not vals:
                continue
            pick = max if op == '>' else min
            _, ext_ts, ext = pick(vals, key=lambda t: t[2])
            n_bad, longest, frm = _breach(vals, op, thr, iv)
            row = (area, f'{obj}\\{ctr}', inst_name, ext, ext_ts, round(100.0 * n_bad / len(vals), 2),
                   round(longest, 1), frm or '', f'{op} {thr:g}: {why}')
            if worst is None or (row[6], row[5]) > (worst[6], worst[5]):
                worst = row
        if worst:
            lines.append(worst)
    # network utilisation: Bytes Total/sec * 8 / Current Bandwidth, per adapter
    for (inst,) in con.execute("SELECT instance FROM counters WHERE object='Network Interface' AND counter='Bytes Total/sec'"):
        bw = con.execute("SELECT max_value FROM counters WHERE object='Network Interface' AND counter='Current Bandwidth' "
                         "AND instance=?", (inst,)).fetchone()
        mx = con.execute("SELECT max_value FROM counters WHERE object='Network Interface' AND counter='Bytes Total/sec' "
                         "AND instance=?", (inst,)).fetchone()
        if bw and bw[0] and mx and mx[0]:
            pct = 100.0 * mx[0] * 8 / bw[0]
            lines.append(('Network', 'Network Interface\\% of bandwidth (max)', inst, round(pct, 2), '', None,
                          None, '', '> 70: link saturated' + (' <-- BREACH' if pct > 70 else '')))
    lines.sort(key=lambda r: (-(r[6] or 0), -(r[5] or 0)))
    _print(['area', 'counter', 'worst_instance', 'extreme', 'extreme_at', '%breach', 'longest_min',
            'longest_from', 'rule'], lines, 40)
    hot = [l for l in lines if (l[6] or 0) >= min_minutes]
    print(f'-- {len(hot)} checks breached for >= {min_minutes} continuous minutes')
    if hot:
        print('VERDICT CEILING: critical is allowed, but only for the areas above that breached for '
              f'>= {min_minutes} min: ' + ', '.join(sorted({f"{l[0]} ({l[1]})" for l in hot})))
    else:
        print(f'VERDICT CEILING: WARNING. No check breached for {min_minutes} continuous minutes, so nothing in this '
              'capture may be called critical or severe, and the machine was not hard to use by these checks. '
              'Trends (leaks) are at most warnings.')
    return lines


def _spec_ids(con, spec):
    obj, ctr, inst = (tuple(spec) + (None,))[:3]
    cids = ids(con, obj, ctr, inst)
    if len(cids) != 1:
        print(f'-- {obj}\\{ctr} [{inst or ""}] matched {len(cids)} counters; give an exact instance')
        return None
    return cids[0]


def _pid_cid(con, spec):
    """The 'ID Process' counter of the same Process instance, or None."""
    obj, ctr, inst = (tuple(spec) + (None,))[:3]
    if obj != 'Process' or inst is None:
        return None
    r = con.execute("SELECT counter_id FROM counters WHERE object='Process' AND counter='ID Process' AND instance=?",
                    (inst,)).fetchone()
    return r[0] if r else None


def link_test(con, x, y, bucket_min=60, start=None, end=None, quiet_frac=0.1):
    """Test a causal link in time: does X still grow after Y stopped?  x, y = (object, counter, instance).
    Per bucket: Y average, X average and X's change from the previous bucket's average (averages, so a saw-tooth
    counter does not fake growth). Buckets where Y is below quiet_frac of its busy level (p90 of the bucket
    averages) are 'quiet'. A change across a PID change of the process behind X is marked and left out.
    Prints X's change per hour in busy vs quiet buckets and the correlation of Y with X's change. A claim that
    Y drives X needs: X grows in busy buckets, X is flat in quiet ones, and a clearly positive r."""
    cx, cy = _spec_ids(con, x), _spec_ids(con, y)
    if cx is None or cy is None:
        return None
    cp = _pid_cid(con, x)
    sec = int(bucket_min * 60)
    rows = con.execute(f'''WITH b AS (SELECT sample_id, {_bucket(sec)} AS bucket FROM samples s
                             WHERE s.ts >= coalesce(?, s.ts) AND s.ts <= coalesce(?, s.ts))
        SELECT b.bucket,
               avg(CASE WHEN v.counter_id = ? THEN v.value END) y_avg,
               avg(CASE WHEN v.counter_id = ? THEN v.value END) x_avg,
               min(CASE WHEN v.counter_id = ? THEN v.value END) pid_min,
               max(CASE WHEN v.counter_id = ? THEN v.value END) pid_max
        FROM b JOIN vals v USING(sample_id) WHERE v.counter_id IN (?, ?, ?)
        GROUP BY b.bucket ORDER BY b.bucket''', (start, end, cy, cx, cp, cp, cx, cy, cp or -1)).fetchall()
    out, prev = [], None
    for bucket, y_avg, x_avg, pmin, pmax in rows:
        if y_avg is None or x_avg is None:
            prev = None
            continue
        pid_changed = pmin != pmax or (prev is not None and prev[1] is not None and pmin != prev[1])
        change = None if prev is None else x_avg - prev[0]
        out.append([bucket, y_avg, x_avg, change, 'PID changed' if pid_changed and prev else ''])
        prev = (x_avg, pmax)
    out = [r for r in out if r[3] is not None]
    if len(out) < 3:
        print('-- link_test: fewer than 3 buckets with both counters')
        return None
    ys = sorted(r[1] for r in out)
    busy_level = ys[int(0.9 * (len(ys) - 1))]
    for r in out:
        r.insert(4, 'quiet' if r[1] < quiet_frac * busy_level else 'busy')
    print(f'-- link_test X = {x[0]}\\{x[1]} [{x[2] if len(x) > 2 else ""}]  vs  Y = {y[0]}\\{y[1]} '
          f'[{y[2] if len(y) > 2 else ""}], bucket {bucket_min} min; quiet = Y < {quiet_frac:g} x {_f(float(busy_level))}')
    _print(['bucket', 'y_avg', 'x_avg', 'x_change', 'state', 'note'], out, MAX_POINTS)
    use = [r for r in out if not r[5]]
    h = bucket_min / 60.0
    summ = {}
    for st in ('busy', 'quiet'):
        rs = [r for r in use if r[4] == st]
        summ[st] = (len(rs), sum(r[3] for r in rs) / (len(rs) * h) if rs else None)
    n = len(use)
    r_val = None
    if n >= 3:
        mx = sum(r[1] for r in use) / n
        my = sum(r[3] for r in use) / n
        sxy = sum((r[1] - mx) * (r[3] - my) for r in use)
        sxx = sum((r[1] - mx) ** 2 for r in use)
        syy = sum((r[3] - my) ** 2 for r in use)
        r_val = sxy / math.sqrt(sxx * syy) if sxx and syy else None
    fmt = lambda v: 'n/a' if v is None else _f(float(v))
    print(f"X change per hour: busy {fmt(summ['busy'][1])} ({summ['busy'][0]} buckets), "
          f"quiet {fmt(summ['quiet'][1])} ({summ['quiet'][0]} buckets); r(Y, X change) = {fmt(r_val)}; "
          f"{len(out) - n} bucket(s) left out for a PID change")
    b, q = summ['busy'][1], summ['quiet'][1]
    if b is None or q is None or b <= 0:
        print('LINK: not shown here (no busy or no quiet buckets, or X does not grow while Y is busy); '
              'say "coincides with", not "caused by".')
    elif abs(q) <= 0.2 * b and (r_val or 0) >= 0.5:
        print('LINK: consistent with Y driving X (X grows with Y and stops when Y stops). Still a correlation.')
    elif q > 0.2 * b and (r_val or 0) >= 0.5:
        print('LINK: partial. X grows faster with Y, but also grows while Y is quiet: Y is not the only driver.')
    elif q > 0.2 * b:
        print('LINK: X keeps growing while Y is quiet: Y does not explain X. Do not claim Y causes X.')
    else:
        print('LINK: weak or unclear; say "coincides with", not "caused by".')
    return out


def leak_rate(con, x, load, start=None, end=None, min_samples=30):
    """A leak's rate per unit of load: X's growth divided by the load served, per segment where the process behind
    X did not change.  x = (object, counter, instance), e.g. ('Process', 'Handle Count', 'w3wp');
    load = a per-second rate counter, e.g. ('ASP.NET Applications', 'Requests/Sec', '__Total__').
    load served = sum(rate x sample interval). Prints growth per 1,000 units of load and per hour, per segment."""
    cx, cl = _spec_ids(con, x), _spec_ids(con, load)
    if cx is None or cl is None:
        return None
    cp = _pid_cid(con, x)
    iv = interval_s(con)
    rows = con.execute('''SELECT s.sample_id, s.ts, vx.value, coalesce(vl.value, 0), vp.value
        FROM samples s JOIN vals vx ON vx.sample_id = s.sample_id AND vx.counter_id = ?
        LEFT JOIN vals vl ON vl.sample_id = s.sample_id AND vl.counter_id = ?
        LEFT JOIN vals vp ON vp.sample_id = s.sample_id AND vp.counter_id = ?
        WHERE s.ts >= coalesce(?, s.ts) AND s.ts <= coalesce(?, s.ts) ORDER BY s.sample_id''',
        (cx, cl, cp or -1, start, end)).fetchall()
    segs, cur = [], None
    for sid, ts, xv, lv, pid in rows:
        if cur is None or pid != cur['pid']:
            cur = {'pid': pid, 't0': ts, 'x0': xv, 'load': 0.0, 'n': 0}
            segs.append(cur)
        cur['t1'], cur['x1'] = ts, xv
        cur['load'] += lv * iv
        cur['n'] += 1
    out = []
    for g in segs:
        if g['n'] < min_samples:
            continue
        hours = g['n'] * iv / 3600.0
        growth = g['x1'] - g['x0']
        out.append((g['pid'] if g['pid'] is not None else '', g['t0'][:19], g['t1'][:19], g['x0'], g['x1'], growth,
                    g['load'], 1000.0 * growth / g['load'] if g['load'] else None, growth / hours if hours else None))
    print(f'-- leak_rate X = {x[0]}\\{x[1]} [{x[2] if len(x) > 2 else ""}] per load {load[0]}\\{load[1]} '
          f'[{load[2] if len(load) > 2 else ""}] (segments of >= {min_samples} samples with one PID)')
    _print(['pid', 'from', 'to', 'x_first', 'x_last', 'growth', 'load_total', 'per_1000_load', 'per_hour'], out, 10)
    return out
