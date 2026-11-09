import { useEffect, useState } from "react";
import { api, patch } from "../api";

export default function Issues() {
  const [rows, setRows] = useState<any[]>([]);
  const [users, setUsers] = useState<any[]>([]);
  const [status, setStatus] = useState("");
  const [me, setMe] = useState<any>(null);
  const load = () => api(`/issues${status ? `?status=${status}` : ""}`).then(setRows);
  useEffect(() => { load(); }, [status]);
  useEffect(() => { api("/users").then(setUsers); api("/auth/me").then(setMe); }, []);
  const act = async (id: string, body: any) => { try { await patch(`/issues/${id}`, body); load(); } catch (e: any) { alert(e.message); } };
  return (
    <>
      <div className="row"><select value={status} onChange={(e) => setStatus(e.target.value)}><option value="">All</option>{["open", "assigned", "fixed", "verified"].map((s) => <option key={s}>{s}</option>)}</select></div>
      <table><thead><tr><th>Asset</th><th>Issue</th><th>Severity</th><th>Status</th><th>Photos (before / after)</th><th>Actions</th></tr></thead>
        <tbody>{rows.map((i) => (
          <tr key={i.id}><td>{i.asset_name}</td><td>{i.type}</td><td>{i.severity}</td><td>{i.status}</td>
            <td className="photos">{i.photos.map((p: any) => <a key={p.id} href={p.url} target="_blank"><img src={p.url} title={p.kind} /></a>)}</td>
            <td>
              {i.status !== "verified" && <select value={i.assigned_to ?? ""} onChange={(e) => e.target.value && act(i.id, { assigned_to: e.target.value })}><option value="">Assign…</option>{users.filter((u) => u.role === "field_staff" || u.role === "supervisor").map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}</select>}
              {i.status === "fixed" && ["manager", "admin"].includes(me?.role) && <button className="btn" onClick={() => act(i.id, { status: "verified" })}>Verify &amp; close</button>}
            </td></tr>))}</tbody></table>
    </>
  );
}
