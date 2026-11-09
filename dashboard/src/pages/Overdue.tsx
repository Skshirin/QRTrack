import { useEffect, useState } from "react";
import { api, post } from "../api";

export default function Overdue() {
  const [rows, setRows] = useState<any[]>([]);
  const [users, setUsers] = useState<any[]>([]);
  const [zones, setZones] = useState<Record<string, string>>({});
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [who, setWho] = useState("");
  const load = () => api("/assets?state=overdue").then(setRows);
  useEffect(() => {
    load(); api("/users").then(setUsers);
    api("/zones").then((z) => setZones(Object.fromEntries(z.map((x: any) => [x.id, x.name]))));
  }, []);
  const days = (d: string) => Math.floor((Date.now() - new Date(d).getTime()) / 86400000);
  const sorted = [...rows].sort((a, b) => days(b.next_due_at) - days(a.next_due_at));
  const toggle = (id: string) => { const s = new Set(sel); s.has(id) ? s.delete(id) : s.add(id); setSel(s); };
  return (
    <>
      <div className="row">
        <select value={who} onChange={(e) => setWho(e.target.value)}><option value="">Assign selected to…</option>{users.filter((u) => u.role !== "admin").map((u) => <option key={u.id} value={u.id}>{u.name} ({u.role})</option>)}</select>
        <button className="btn" disabled={!who || !sel.size} onClick={async () => { await post("/assets/assign", { asset_ids: [...sel], user_id: who }); setSel(new Set()); load(); }}>Assign {sel.size || ""}</button>
      </div>
      <table><thead><tr><th></th><th>Asset</th><th>Zone</th><th>Days overdue</th><th>Assigned</th></tr></thead>
        <tbody>{sorted.map((a) => (
          <tr key={a.id}><td><input type="checkbox" checked={sel.has(a.id)} onChange={() => toggle(a.id)} /></td><td>{a.name}</td><td>{zones[a.zone_id]}</td>
            <td style={{ color: "var(--red)" }}>{days(a.next_due_at)}</td><td>{users.find((u) => u.id === a.assigned_to)?.name ?? "–"}</td></tr>))}</tbody></table>
      {!rows.length && <p>Nothing overdue 🎉</p>}
    </>
  );
}
