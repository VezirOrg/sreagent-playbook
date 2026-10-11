#!/usr/bin/env python3
r"""Synthetic PerfMon capture (PDH-CSV) with planted problems and their ground truth (test plan L01, L02, T16).

Synthetic data only: the host is SYNTH01, process names are generic (svchost, w3wp, leaker, cpuhog, ...). The counter
set is the playbook's own (package/collector: the 36 + G1 + G2, + G3 with --web), so the skill is tested on exactly
what the recorder writes.

Planted problems (each optional, --plant a,b,...), times relative to the capture start:
  leak   process 'leaker': Private Bytes and Working Set grow LEAK_MB_PER_H per hour for the whole capture, one PID
  cpu    machine CPU (Processor Information _Total) >= 95 % for CPU_MIN minutes, driven by process 'cpuhog'
  disk   LogicalDisk C: Avg. Disk sec/Read and sec/Write 0.08 s for DISK_MIN minutes
  nic    Network Interface Bytes Total/sec at 90 % of Current Bandwidth for NIC_MIN minutes
  stall  CPU 100 % for 30 s (20-40 s) every 30 minutes (the OPEN-2 case)
  restart process 'w3wp' gets a new PID once (PID-change artifact; not a problem)

Usage:
  make_capture.py --out cap.csv [--truth truth.json] [--hours 2] [--interval 10] [--start 2026-10-01T08:00:00]
                  [--procs 20] [--plant leak,cpu,disk,nic,stall,restart] [--web] [--dayfirst] [--seed 1]
                  [--from-row N --to-row M]   (write only rows N..M-1: consecutive parts of one capture)
"""
import argparse
import csv
import datetime as dt
import json
import math
import os
import random
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
COLLECTOR = os.path.join(HERE, '..', '..', 'package', 'collector')
HOST = 'SYNTH01'
LEAK_MB_PER_H = 200
CPU_MIN, DISK_MIN, NIC_MIN = 12, 6, 6
BANDWIDTH = 1_000_000_000  # bits/s


def read_counters(name):
    with open(os.path.join(COLLECTOR, name), encoding='utf-8') as f:
        return [l.strip() for l in f if l.strip() and not l.startswith('#')]


def counter_set(web):
    s = read_counters('PerfmonBlackbox.counters.txt') + read_counters('PerfmonBlackbox.counters-g1-system.txt') + \
        read_counters('PerfmonBlackbox.counters-g2-process.txt')
    if web:
        s += read_counters('PerfmonBlackbox.counters-g3-web.txt')
    return s


def instances(obj, procs):
    if obj == 'Process':
        names = ['_Total', 'Idle', 'System', 'w3wp', 'leaker', 'cpuhog', 'sqlwriter', 'MsMpEng']
        i = 0
        while len(names) < procs + 2:
            names.append('svchost' if i == 0 else f'svchost#{i}')
            i += 1
        return names
    return {
        'Processor Information': ['_Total', '0,_Total', '0,0', '0,1', '0,2', '0,3'],
        'LogicalDisk': ['C:', 'D:', '_Total'],
        'Network Interface': ['Synthetic Ethernet Adapter'],
        'Paging File': ['_Total'],
        '.NET CLR Memory': ['_Global_', 'w3wp'],
        'ASP.NET Applications': ['__Total__'],
        'Web Service': ['_Total'],
    }.get(obj, [None])


def expand(counters, procs):
    cols = []
    for c in counters:
        obj_inst, ctr = c[1:].rsplit('\\', 1)
        if '(' in obj_inst:
            obj, inst = obj_inst.split('(', 1)
            inst = inst[:-1]
            insts = instances(obj, procs) if inst == '*' else [inst]
        else:
            obj, insts = obj_inst, [None]
        for i in insts:
            path = f'\\\\{HOST}\\{obj}' + (f'({i})' if i is not None else '') + f'\\{ctr}'
            cols.append((path, obj, i, ctr))
    return cols


class Plan:
    def __init__(self, n_rows, interval, plant, rnd):
        self.iv = interval
        self.n = n_rows
        self.plant = set(plant)
        span = n_rows * interval
        # episodes placed in fixed fractions of the capture, so they never overlap
        self.cpu = self._ep(0.20, CPU_MIN * 60) if 'cpu' in self.plant else None
        self.disk = self._ep(0.45, DISK_MIN * 60) if 'disk' in self.plant else None
        self.nic = self._ep(0.70, NIC_MIN * 60) if 'nic' in self.plant else None
        self.stalls = []
        if 'stall' in self.plant:
            t = 15 * 60
            while t + 60 < span:
                busy = [e for e in (self.cpu, self.disk, self.nic) if e]
                d = rnd.choice((20, 30, 40))
                if not any(a - 120 <= t <= b + 120 for a, b in busy):
                    self.stalls.append((t, t + d))
                t += 30 * 60
        self.restart = (int(0.55 * n_rows)) if 'restart' in self.plant else None

    def _ep(self, frac, dur):
        start = int(frac * self.n) * self.iv
        return start, start + dur

    @staticmethod
    def inside(ep, t):
        return ep is not None and ep[0] <= t < ep[1]

    def stall(self, t):
        return any(a <= t < b for a, b in self.stalls)


def value(col, row, t, plan, rnd, procs):
    path, obj, inst, ctr = col
    jitter = lambda base, pct=0.05: base * (1 + rnd.uniform(-pct, pct))
    cpu_busy = plan.inside(plan.cpu, t)
    stall = plan.stall(t)
    hours = t / 3600.0
    if obj == 'Processor Information':
        if ctr == '% Processor Time':
            v = 100.0 if stall else (rnd.uniform(95.5, 99.5) if cpu_busy else jitter(18, 0.4))
            return min(v, 100.0)
        if ctr == '% Privileged Time':
            return jitter(4, 0.4)
        if ctr == '% User Time':
            return 90.0 if (cpu_busy or stall) else jitter(14, 0.4)
        if ctr == '% Processor Performance':
            return jitter(100, 0.02)
        if ctr == 'Parking Status':
            return 0.0
    if obj == 'Process':
        if inst == '_Total':
            if ctr == '% Processor Time':
                return 400.0 if (cpu_busy or stall) else jitter(70, 0.3)
            if ctr == 'ID Process':
                return 0.0
            return jitter(4e9 if 'Bytes' in ctr or 'Working' in ctr else 2000)
        pid = 1000 + 4 * (zlib.crc32(inst.encode()) % 5000)
        if inst == 'Idle':
            pid = 0
        if inst == 'w3wp' and plan.restart is not None and row >= plan.restart:
            pid += 4
        if ctr == 'ID Process':
            return float(pid)
        if ctr == '% Processor Time':
            if inst == 'cpuhog':
                return jitter(380, 0.02) if cpu_busy else (390.0 if stall else jitter(0.5, 0.5))
            if inst == 'Idle':
                return 20.0 if (cpu_busy or stall) else jitter(330, 0.05)
            return jitter(1.5, 0.8)
        if ctr in ('Private Bytes', 'Working Set', 'Working Set - Private'):
            base = 300e6 if inst in ('w3wp', 'leaker', 'sqlwriter') else 40e6
            if inst == 'leaker' and 'leak' in plan.plant:
                base += LEAK_MB_PER_H * 1e6 * hours
            return jitter(base, 0.002)
        if ctr == 'Handle Count':
            return float(int(jitter(600, 0.01)))
        if ctr == 'Thread Count':
            return float(int(jitter(25, 0.04)))
        if ctr == 'IO Data Operations/sec':
            return jitter(5, 0.8)
        if ctr.startswith('Pool'):
            return jitter(60e3 if 'Nonpaged' in ctr else 300e3, 0.01)
    if obj == 'LogicalDisk':
        slow = plan.inside(plan.disk, t) and inst == 'C:'
        if ctr in ('Avg. Disk sec/Read', 'Avg. Disk sec/Write'):
            return jitter(0.08, 0.1) if slow else jitter(0.002, 0.4)
        if ctr == 'Avg. Disk Write Queue Length':
            return jitter(6, 0.2) if slow else jitter(0.05, 0.5)
        if ctr == 'Current Disk Queue Length':
            return float(int(jitter(5, 0.3))) if slow else 0.0
        if ctr == '% Idle Time':
            return jitter(5, 0.5) if slow else jitter(97, 0.02)
        if ctr == '% Free Space':
            return 55.0 if inst != 'D:' else 80.0
        if ctr in ('Disk Bytes/sec',):
            return jitter(2e6, 0.5)
        return jitter(40, 0.5)
    if obj == 'Network Interface':
        if ctr == 'Current Bandwidth':
            return float(BANDWIDTH)
        if ctr == 'Bytes Total/sec':
            return jitter(0.9 * BANDWIDTH / 8, 0.03) if plan.inside(plan.nic, t) else jitter(2e5, 0.5)
        if ctr == 'Output Queue Length':
            return 0.0
        return 0.0
    if obj == 'Memory':
        leak = LEAK_MB_PER_H * hours if 'leak' in plan.plant else 0.0
        return {
            '% Committed Bytes In Use': 40 + leak / 160,
            'Available MBytes': max(8192 - 2000 - leak, 300.0),
            'Commit Limit': 16e9, 'Committed Bytes': 6.4e9 + leak * 1e6,
            'Pool Nonpaged Bytes': 2e8, 'Pool Paged Bytes': 4e8, 'System Cache Resident Bytes': 3e8,
            'Free System Page Table Entries': 1.6e7, 'Pages Input/sec': 0.0, 'Pages/sec': 1.0,
        }.get(ctr, 0.0) * (1 + rnd.uniform(-0.001, 0.001))
    if obj == 'System':
        if ctr == 'System Up Time':
            return 86400.0 + t
        if ctr == 'Processor Queue Length':
            return float(int(rnd.uniform(9, 14))) if (cpu_busy or stall) else float(int(rnd.uniform(0, 2)))
        return jitter(4000, 0.2)
    if obj in ('TCPv4', 'TCPv6'):
        if ctr == 'Connections Reset':
            return 100.0 + row // 60  # cumulative
        return float(int(jitter(40 if obj == 'TCPv4' else 2, 0.1)))
    if obj == 'Paging File':
        return jitter(3, 0.1)
    return jitter(1, 0.5)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', required=True)
    ap.add_argument('--truth')
    ap.add_argument('--hours', type=float, default=2.0)
    ap.add_argument('--interval', type=int, default=10)
    ap.add_argument('--start', default='2026-10-01T08:00:00')
    ap.add_argument('--procs', type=int, default=20)
    ap.add_argument('--plant', default='leak,cpu,disk,nic,stall,restart')
    ap.add_argument('--web', action='store_true')
    ap.add_argument('--dayfirst', action='store_true')
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--from-row', type=int, default=0)
    ap.add_argument('--to-row', type=int)
    a = ap.parse_args()
    rnd = random.Random(a.seed)
    n = int(a.hours * 3600 / a.interval)
    plant = [p for p in a.plant.split(',') if p]
    unknown = set(plant) - {'leak', 'cpu', 'disk', 'nic', 'stall', 'restart'}
    if unknown:
        sys.exit(f'unknown plant: {", ".join(sorted(unknown))}')
    plan = Plan(n, a.interval, plant, rnd)
    cols = expand(counter_set(a.web), a.procs)
    t0 = dt.datetime.fromisoformat(a.start)
    fmt = '%d/%m/%Y %H:%M:%S.%f' if a.dayfirst else '%m/%d/%Y %H:%M:%S.%f'
    to_row = n if a.to_row is None else min(a.to_row, n)
    with open(a.out, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL, lineterminator='\r\n')
        w.writerow(['(PDH-CSV 4.0) (Coordinated Universal Time)(0)'] + [c[0] for c in cols])
        for row in range(n):
            t = row * a.interval
            vals = [value(c, row, t, plan, rnd, a.procs) for c in cols]  # always drawn: parts stay identical
            if a.from_row <= row < to_row:
                ts = (t0 + dt.timedelta(seconds=t)).strftime(fmt)[:-3]
                w.writerow([ts] + [f'{v:.6f}'.rstrip('0').rstrip('.') if v != int(v) else str(int(v)) for v in vals])
    if a.truth:
        iso = lambda s: (t0 + dt.timedelta(seconds=s)).isoformat(sep=' ')
        truth = {'host': HOST, 'interval_s': a.interval, 'first_ts': iso(0), 'last_ts': iso((n - 1) * a.interval),
                 'rows': n, 'columns': len(cols), 'problems': []}
        if 'leak' in plan.plant:
            truth['problems'].append({'id': 'leak', 'process': 'leaker', 'counter': 'Private Bytes',
                                      'per_hour_bytes': LEAK_MB_PER_H * 1e6, 'from': iso(0), 'to': iso((n - 1) * a.interval)})
        for pid, ep, drv, ctr in (('cpu', plan.cpu, 'cpuhog', 'Processor Information\\% Processor Time'),
                                  ('disk', plan.disk, 'C:', 'LogicalDisk\\Avg. Disk sec/Read'),
                                  ('nic', plan.nic, 'Synthetic Ethernet Adapter', 'Network Interface\\Bytes Total/sec')):
            if ep:
                truth['problems'].append({'id': pid, 'driver': drv, 'counter': ctr, 'from': iso(ep[0]),
                                          'to': iso(ep[1] - a.interval), 'minutes': (ep[1] - ep[0]) / 60})
        if plan.stalls:
            truth['problems'].append({'id': 'stall', 'driver': 'cpuhog', 'episodes': [
                {'from': iso(s), 'to': iso(e - a.interval), 'seconds': e - s} for s, e in plan.stalls]})
        if plan.restart is not None:
            truth['artifacts'] = [{'id': 'restart', 'process': 'w3wp', 'at': iso(plan.restart * a.interval)}]
        with open(a.truth, 'w', encoding='utf-8') as f:
            json.dump(truth, f, indent=1)
    print(f'rows={to_row - a.from_row} columns={len(cols)} interval={a.interval} plant={",".join(plant) or "-"}')


if __name__ == '__main__':
    main()
