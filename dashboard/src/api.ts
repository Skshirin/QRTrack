const BASE = "/api/v1";
export type User = { id: string; name: string; role: string };

let access = localStorage.getItem("access") || "";
let refreshTok = localStorage.getItem("refresh") || "";

export function setTokens(a: string, r: string) {
  access = a; refreshTok = r;
  localStorage.setItem("access", a); localStorage.setItem("refresh", r);
}
export function logout() { localStorage.clear(); location.reload(); }

async function refresh(): Promise<boolean> {
  if (!refreshTok) return false;
  const res = await fetch(`${BASE}/auth/refresh`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refresh: refreshTok }) });
  if (!res.ok) return false;
  const d = await res.json(); setTokens(d.access, d.refresh); return true;
}

async function raw(path: string, opts: RequestInit = {}, retry = true): Promise<Response> {
  const res = await fetch(BASE + path, { ...opts, headers: { "Content-Type": "application/json", Authorization: `Bearer ${access}`, ...(opts.headers || {}) } });
  if (res.status === 401 && retry && (await refresh())) return raw(path, opts, false);
  if (!res.ok) throw new Error(await res.text());
  return res;
}

export async function api<T = any>(path: string, opts: RequestInit = {}): Promise<T> {
  return (await raw(path, opts)).json();
}
export const post = <T = any>(path: string, body: unknown) => api<T>(path, { method: "POST", body: JSON.stringify(body) });
export const patch = <T = any>(path: string, body: unknown) => api<T>(path, { method: "PATCH", body: JSON.stringify(body) });

export async function download(path: string, filename: string, opts: RequestInit = {}) {
  const blob = await (await raw(path, opts)).blob();
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob); a.download = filename; a.click();
  URL.revokeObjectURL(a.href);
}

export async function login(phone: string, code: string) {
  const res = await fetch(`${BASE}/auth/verify`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phone, code }) });
  if (!res.ok) throw new Error("Wrong phone or PIN");
  const d = await res.json(); setTokens(d.access, d.refresh); return d.user as User;
}
