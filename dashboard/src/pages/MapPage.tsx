import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import { api } from "../api";

const COLORS: Record<string, string> = { done: "#2e9e4f", due_today: "#f0a500", overdue: "#d93025", inactive: "#9aa0a6" };

export default function MapPage() {
  const el = useRef<HTMLDivElement>(null);
  const map = useRef<maplibregl.Map | null>(null);
  const [assets, setAssets] = useState<any[]>([]);
  const [zones, setZones] = useState<any[]>([]);
  const [types, setTypes] = useState<any[]>([]);
  const [f, setF] = useState({ zone: "", type: "", state: "" });

  useEffect(() => {
    Promise.all([api("/assets"), api("/zones"), api("/asset-types")]).then(([a, z, t]) => { setAssets(a); setZones(z); setTypes(t); });
  }, []);

  const filtered = assets.filter((a) => (!f.zone || a.zone_id === f.zone) && (!f.type || a.type_id === f.type) && (!f.state || a.state === f.state));
  const geo = (items: any[]) => ({ type: "FeatureCollection", features: items.map((a) => ({ type: "Feature", geometry: { type: "Point", coordinates: [a.lng, a.lat] }, properties: a })) });

  useEffect(() => {
    if (!el.current || map.current || !assets.length) return;
    const m = new maplibregl.Map({
      container: el.current, center: [assets[0].lng, assets[0].lat], zoom: 16,
      style: { version: 8, sources: { osm: { type: "raster", tileSize: 256, attribution: "© OpenStreetMap contributors", tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"] } }, layers: [{ id: "osm", type: "raster", source: "osm" }] },
    });
    m.addControl(new maplibregl.NavigationControl());
    m.on("load", () => {
      m.addSource("zones", { type: "geojson", data: { type: "FeatureCollection", features: zones.filter((z) => z.boundary).map((z) => ({ type: "Feature", geometry: z.boundary, properties: { name: z.name } })) } as any });
      m.addLayer({ id: "zones-fill", type: "fill", source: "zones", paint: { "fill-color": "#14532d", "fill-opacity": 0.08 } });
      m.addLayer({ id: "zones-line", type: "line", source: "zones", paint: { "line-color": "#14532d", "line-width": 1.5 } });
      m.addSource("assets", { type: "geojson", data: geo(assets) as any });
      m.addLayer({ id: "assets", type: "circle", source: "assets", paint: {
        "circle-radius": 7, "circle-stroke-color": "#fff", "circle-stroke-width": 1.5,
        "circle-color": ["match", ["get", "state"], "done", COLORS.done, "due_today", COLORS.due_today, "overdue", COLORS.overdue, COLORS.inactive] } });
      m.on("click", "assets", async (e) => {
        const p: any = e.features![0].properties;
        const hist = await api(`/inspections?asset_id=${p.id}&limit=1`).catch(() => []);
        const last = hist[0];
        const html = `<b>${p.name}</b><br/>Status: ${p.state}<br/>Next due: ${p.next_due_at?.slice(0, 10) ?? "–"}` +
          (last ? `<br/>Last: ${last.scanned_at.slice(0, 16).replace("T", " ")} by ${last.user_name} (${last.result})${last.photos[0] ? `<br/><img src="${last.photos[0].url}" width="200"/>` : ""}` : "<br/>No inspections yet");
        new maplibregl.Popup().setLngLat((e.features![0].geometry as any).coordinates).setHTML(html).addTo(m);
      });
      m.on("mouseenter", "assets", () => (m.getCanvas().style.cursor = "pointer"));
      m.on("mouseleave", "assets", () => (m.getCanvas().style.cursor = ""));
    });
    map.current = m;
  }, [assets, zones]);

  useEffect(() => { (map.current?.getSource("assets") as maplibregl.GeoJSONSource | undefined)?.setData(geo(filtered) as any); }, [f, assets]);

  return (
    <>
      <div className="row">
        <select value={f.zone} onChange={(e) => setF({ ...f, zone: e.target.value })}><option value="">All zones</option>{zones.map((z) => <option key={z.id} value={z.id}>{z.name}</option>)}</select>
        <select value={f.type} onChange={(e) => setF({ ...f, type: e.target.value })}><option value="">All types</option>{types.map((t) => <option key={t.id} value={t.id}>{t.name.en}</option>)}</select>
        <select value={f.state} onChange={(e) => setF({ ...f, state: e.target.value })}><option value="">All statuses</option><option value="done">Done (green)</option><option value="due_today">Due today (amber)</option><option value="overdue">Overdue (red)</option><option value="inactive">Inactive (grey)</option></select>
        <span>{filtered.length} assets</span>
      </div>
      <div id="map" ref={el} />
    </>
  );
}
