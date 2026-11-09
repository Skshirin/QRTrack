import { useEffect, useState } from "react";
import { api, login, logout, User } from "./api";
import Overview from "./pages/Overview";
import MapPage from "./pages/MapPage";
import Overdue from "./pages/Overdue";
import Issues from "./pages/Issues";
import Review from "./pages/Review";
import Registry from "./pages/Registry";
import Reports from "./pages/Reports";

const PAGES: Record<string, { label: string; el: () => JSX.Element; roles: string[] }> = {
  overview: { label: "Overview", el: Overview, roles: ["supervisor", "manager", "admin"] },
  map: { label: "Campus map", el: MapPage, roles: ["supervisor", "manager", "admin"] },
  overdue: { label: "Overdue", el: Overdue, roles: ["supervisor", "manager", "admin"] },
  issues: { label: "Issues", el: Issues, roles: ["supervisor", "manager", "admin"] },
  review: { label: "Inspection review", el: Review, roles: ["supervisor", "manager", "admin"] },
  registry: { label: "Registry & tags", el: Registry, roles: ["supervisor", "admin"] },
  reports: { label: "Staff & reports", el: Reports, roles: ["supervisor", "manager", "admin"] },
};

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [ready, setReady] = useState(false);
  const [page, setPage] = useState("overview");
  const [phone, setPhone] = useState("+919999900002");
  const [pin, setPin] = useState("1234");
  const [err, setErr] = useState("");

  useEffect(() => {
    api("/auth/me").then(setUser).catch(() => {}).finally(() => setReady(true));
  }, []);

  if (!ready) return null;
  if (!user || user.role === "field_staff")
    return (
      <form className="login" onSubmit={async (e) => { e.preventDefault(); try { setUser(await login(phone, pin)); setErr(""); } catch (x: any) { setErr(x.message); } }}>
        <h2>Kanha QR Monitoring</h2>
        <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="Phone" />
        <input value={pin} onChange={(e) => setPin(e.target.value)} placeholder="PIN" type="password" />
        <button className="btn">Sign in</button>
        {user?.role === "field_staff" && <span>Field staff use the mobile app.</span>}
        {err && <span style={{ color: "var(--red)" }}>{err}</span>}
      </form>
    );

  const allowed = Object.entries(PAGES).filter(([, p]) => p.roles.includes(user.role));
  const Current = (PAGES[page] && PAGES[page].roles.includes(user.role) ? PAGES[page] : allowed[0][1]).el;
  return (
    <>
      <header>
        <b>Kanha QR</b>
        <nav>{allowed.map(([k, p]) => <button key={k} className={k === page ? "on" : ""} onClick={() => setPage(k)}>{p.label}</button>)}</nav>
        <span style={{ marginLeft: "auto" }}>{user.name} ({user.role}) <button className="btn grey" onClick={logout}>Log out</button></span>
      </header>
      <main><Current /></main>
    </>
  );
}
