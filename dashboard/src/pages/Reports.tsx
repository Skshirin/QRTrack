import { useEffect, useState } from "react";
import { api, download } from "../api";

export default function Reports() {
  const [days, setDays] = useState(7);
  const [rows, setRows] = useState<any[]>([]);
  useEffect(() => { api(`/reports/staff?days=${days}`).then(setRows); }, [days]);
  const since = new Date(Date.now() - days * 86400000).toISOString();
  return (
    <>
      <div className="row">
        <select value={days} onChange={(e) => setDays(+e.target.value)}>{[7, 14, 30, 90].map((d) => <option key={d} value={d}>Last {d} days</option>)}</select>
        <button className="btn" onClick={() => download("/reports/weekly.pdf", "kanha-weekly.pdf").catch((e) => alert(e.message))}>Weekly PDF</button>
        <button className="btn" onClick={() => download(`/export.csv?date_from=${encodeURIComponent(since)}`, "kanha-export.csv").catch((e) => alert(e.message))}>CSV export</button>
      </div>
      <h3>Inspections per person per day</h3>
      <table><thead><tr><th>Day</th><th>Person</th><th>Inspections</th></tr></thead>
        <tbody>{rows.map((r, i) => <tr key={i}><td>{r.day}</td><td>{r.user}</td><td>{r.inspections}</td></tr>)}</tbody></table>
    </>
  );
}
