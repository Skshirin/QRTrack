import { useEffect, useState } from "react";
import { api, patch } from "../api";

export default function Review() {
  const [rows, setRows] = useState<any[]>([]);
  const [flaggedOnly, setFlagged] = useState(true);
  const load = () => api(`/inspections?limit=100${flaggedOnly ? "&flagged=true" : ""}`).then(setRows);
  useEffect(() => { load(); }, [flaggedOnly]);
  const decide = async (id: string, decision: string) => { await patch(`/inspections/${id}/review`, { decision }); load(); };
  return (
    <>
      <div className="row"><label><input type="checkbox" checked={flaggedOnly} onChange={(e) => setFlagged(e.target.checked)} /> Flagged only</label></div>
      <table><thead><tr><th>When</th><th>Asset</th><th>By</th><th>Result</th><th>Evidence</th><th>Flags</th><th>Photos</th><th>Review</th></tr></thead>
        <tbody>{rows.map((i) => (
          <tr key={i.id}><td>{i.scanned_at.slice(0, 16).replace("T", " ")}</td><td>{i.asset_name ?? "unknown tag"}</td><td>{i.user_name}</td><td>{i.result}</td>
            <td>{i.distance_m != null ? `${Math.round(i.distance_m)} m (±${Math.round(i.accuracy_m ?? 0)})` : "no GPS"}</td>
            <td>{i.flags.map((f: string) => <span className="badge" key={f}>{f.replace("_", " ")}</span>)}</td>
            <td className="photos">{i.photos.map((p: any) => <a key={p.id} href={p.url} target="_blank"><img src={p.url} /></a>)}</td>
            <td>{i.review_status === "pending" ? <><button className="btn" onClick={() => decide(i.id, "approved")}>Approve</button> <button className="btn red" onClick={() => decide(i.id, "rejected")}>Reject</button></> : i.review_status}</td></tr>))}</tbody></table>
    </>
  );
}
