import { useEffect, useState } from "react";
import { api } from "../api";

type Bucket = { name: string; due: number; ok: number; pct: number | null };

export default function Overview() {
  const [d, setD] = useState<any>(null);
  useEffect(() => { api("/reports/overview").then(setD); }, []);
  if (!d) return <p>Loading…</p>;
  const rows = (o: Record<string, Bucket>) => Object.values(o).map((v) => (
    <tr key={v.name}><td>{v.name}</td><td>{v.pct ?? "–"}{v.pct != null && "%"}</td><td>{v.ok}/{v.due}</td></tr>));
  return (
    <>
      <div className="cards">
        <div className="card"><div className="n">{d.overall.pct ?? "–"}{d.overall.pct != null && "%"}</div>Compliance (7 days)</div>
        <div className="card"><div className="n" style={{ color: "var(--red)" }}>{d.overdue}</div>Overdue assets</div>
        <div className="card"><div className="n">{d.open_issues}</div>Open issues</div>
        <div className="card"><div className="n">{d.inspections_today}</div>Inspections today</div>
        <div className="card"><div className="n">{d.flagged}</div>Flagged to review</div>
      </div>
      <h3>12-week trend</h3>
      <div className="bars">{d.trend.map((t: any) => <div key={t.week_end} title={t.week_end} style={{ height: `${t.pct ?? 0}%` }}>{t.pct != null ? Math.round(t.pct) : ""}</div>)}</div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginTop: 16 }}>
        <div><h3>By zone</h3><table><thead><tr><th>Zone</th><th>%</th><th>On time</th></tr></thead><tbody>{rows(d.by_zone)}</tbody></table></div>
        <div><h3>By asset type</h3><table><thead><tr><th>Type</th><th>%</th><th>On time</th></tr></thead><tbody>{rows(d.by_type)}</tbody></table></div>
      </div>
    </>
  );
}
