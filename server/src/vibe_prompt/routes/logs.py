"""Web log viewer — served at /logs, protected by admin token or localhost."""
from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Header, HTTPException, Request
from fastapi.responses import HTMLResponse

router = APIRouter()


def _is_localhost(request: Request) -> bool:
    client = request.client
    return client is not None and client.host in ("127.0.0.1", "::1", "localhost")


@router.get("/logs", response_class=HTMLResponse, include_in_schema=False)
async def logs_page(
    request: Request,
    x_admin_token: str | None = Header(default=None),
    limit: int = 200,
) -> HTMLResponse:
    settings = request.app.state.settings
    if not _is_localhost(request) and x_admin_token != settings.ADMIN_TOKEN:
        raise HTTPException(status_code=403, detail="Forbidden")

    rows = await _fetch_logs(settings.API_KEY_DB, limit)
    html = _render_html(rows)
    return HTMLResponse(content=html)


async def _fetch_logs(db_path: str, limit: int) -> list[dict]:
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT
                r.timestamp,
                r.status,
                r.audio_duration_ms,
                r.processing_ms,
                CASE
                    WHEN r.audio_duration_ms > 0
                    THEN ROUND(r.processing_ms / r.audio_duration_ms, 2)
                    ELSE NULL
                END AS rtf,
                r.language_detected,
                r.error_detail,
                k.label AS key_label
            FROM request_log r
            LEFT JOIN api_keys k ON k.id = r.api_key_id
            ORDER BY r.id DESC
            LIMIT ?
            """,
            (limit,),
        ) as cursor:
            rows = [dict(row) for row in await cursor.fetchall()]
    return rows


def _render_html(rows: list[dict]) -> str:
    def _td(val: object, cls: str = "") -> str:
        text = "" if val is None else str(val)
        return f'<td class="{cls}">{text}</td>'

    def _row(r: dict) -> str:
        ts = (r["timestamp"] or "")[:19].replace("T", " ")
        status = r["status"] or ""
        status_cls = "ok" if status == "success" else "err"
        audio = f'{r["audio_duration_ms"] / 1000:.1f}s' if r["audio_duration_ms"] else "—"
        proc = f'{r["processing_ms"]:.0f}ms' if r["processing_ms"] else "—"
        rtf = f'{r["rtf"]:.2f}' if r["rtf"] is not None else "—"
        lang = r["language_detected"] or "—"
        key = r["key_label"] or "local"
        err = (r["error_detail"] or "")[:120]
        return (
            "<tr>"
            + _td(ts, "ts")
            + _td(status, status_cls)
            + _td(audio)
            + _td(proc)
            + _td(rtf)
            + _td(lang)
            + _td(key)
            + _td(err, "err-detail")
            + "</tr>"
        )

    rows_html = "\n".join(_row(r) for r in rows)
    count = len(rows)

    return f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="30">
<title>Vibe Prompt — Logs</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 13px;
    background: #0d1117;
    color: #c9d1d9;
    padding: 24px;
  }}
  h1 {{ font-size: 18px; color: #58a6ff; margin-bottom: 4px; }}
  .meta {{ color: #8b949e; font-size: 12px; margin-bottom: 20px; }}
  table {{
    width: 100%;
    border-collapse: collapse;
  }}
  th {{
    text-align: left;
    padding: 8px 12px;
    border-bottom: 1px solid #30363d;
    color: #8b949e;
    font-weight: 600;
    white-space: nowrap;
  }}
  td {{
    padding: 7px 12px;
    border-bottom: 1px solid #21262d;
    white-space: nowrap;
  }}
  tr:hover td {{ background: #161b22; }}
  .ts {{ color: #8b949e; }}
  .ok {{ color: #3fb950; font-weight: 600; }}
  .err {{ color: #f85149; font-weight: 600; }}
  .err-detail {{ color: #f85149; white-space: normal; max-width: 320px; }}
</style>
</head>
<body>
<h1>Vibe Prompt — Request Log</h1>
<p class="meta">Mostrando los últimos {count} requests &nbsp;·&nbsp; Auto-refresh cada 30s</p>
<table>
  <thead>
    <tr>
      <th>Timestamp (UTC)</th>
      <th>Status</th>
      <th>Audio</th>
      <th>Inference</th>
      <th>RTF</th>
      <th>Lang</th>
      <th>API Key</th>
      <th>Error</th>
    </tr>
  </thead>
  <tbody>
{rows_html}
  </tbody>
</table>
</body>
</html>"""
