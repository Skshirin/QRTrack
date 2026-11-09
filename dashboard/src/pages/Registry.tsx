import { useEffect, useState } from "react";
import { api, download, post } from "../api";

export default function Registry() {
  const [assets, setAssets] = useState<any[]>([]);
  const [zones, setZones] = useState<any[]>([]);
  const [types, setTypes] = useState<any[]>([]);
  const [free, setFree] = useState<any[]>([]);
  const [count, setCount] = useState(20);
  const [form, setForm] = useState({ name: "", type_id: "", zone_id: "", lat: "", lng: "" });
  const [link, setLink] = useState({ code: "", asset_id: "" });
  const load = () => Promise.all([api("/assets"), api("/zones"), api("/asset-types"), api("/tags?linked=false")]).then(([a, z, t, f]) => { setAssets(a); setZones(z); setTypes(t); setFree(f); });
  useEffect(() => { load(); }, []);
  const tname = (id: string) => types.find((t) => t.id === id)?.name.en;
  const zname = (id: string) => zones.find((z) => z.id === id)?.name;
  const wrap = (fn: () => Promise<any>) => async () => { try { await fn(); await load(); } catch (e: any) { alert(e.message); } };
  return (
    <>
      <div className="card" style={{ marginBottom: 12 }}>
        <b>Print tags (admin)</b>{" "}
        <input type="number" value={count} min={1} max={500} onChange={(e) => setCount(+e.target.value)} style={{ width: 80 }} />{" "}
        <button className="btn" onClick={wrap(() => download("/tags/batch", "kanha-tags.pdf", { method: "POST", body: JSON.stringify({ count }) }))}>Generate A4 sheet PDF</button>
        <span> Unlinked tags available: {free.length}</span>
      </div>
      <div className="card" style={{ marginBottom: 12 }}>
        <b>Link a tag to an asset</b>{" "}
        <select value={link.code} onChange={(e) => setLink({ ...link, code: e.target.value })}><option value="">Tag…</option>{free.map((t) => <option key={t.code}>{t.code}</option>)}</select>{" "}
        <select value={link.asset_id} onChange={(e) => setLink({ ...link, asset_id: e.target.value })}><option value="">Asset…</option>{assets.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>{" "}
        <button className="btn" disabled={!link.code || !link.asset_id} onClick={wrap(() => post(`/tags/${link.code}/link`, { asset_id: link.asset_id }))}>Link / replace</button>
      </div>
      <div className="card" style={{ marginBottom: 12 }}>
        <b>New asset</b>{" "}
        <input placeholder="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />{" "}
        <select value={form.type_id} onChange={(e) => setForm({ ...form, type_id: e.target.value })}><option value="">Type…</option>{types.map((t) => <option key={t.id} value={t.id}>{t.name.en}</option>)}</select>{" "}
        <select value={form.zone_id} onChange={(e) => setForm({ ...form, zone_id: e.target.value })}><option value="">Zone…</option>{zones.map((z) => <option key={z.id} value={z.id}>{z.name}</option>)}</select>{" "}
        <input placeholder="Lat" value={form.lat} onChange={(e) => setForm({ ...form, lat: e.target.value })} style={{ width: 100 }} />{" "}
        <input placeholder="Lng" value={form.lng} onChange={(e) => setForm({ ...form, lng: e.target.value })} style={{ width: 100 }} />{" "}
        <button className="btn" onClick={wrap(() => post("/assets", { ...form, lat: +form.lat, lng: +form.lng }))}>Add</button>
      </div>
      <table><thead><tr><th>Name</th><th>Type</th><th>Zone</th><th>Status</th><th>Interval</th><th>Next due</th></tr></thead>
        <tbody>{assets.map((a) => <tr key={a.id}><td>{a.name}</td><td>{tname(a.type_id)}</td><td>{zname(a.zone_id)}</td><td>{a.state}</td><td>{a.interval_days} d</td><td>{a.next_due_at?.slice(0, 10)}</td></tr>)}</tbody></table>
    </>
  );
}
