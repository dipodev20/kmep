"""
KMEP Minimal Backend — emergency-only fallback.

Клиентский StreamResolver (Dart + JS-рантайм) пытается сам выполнить
player.js. Бэкенд намеренно НЕ дублирует свою реализацию n-sig/cipher —
использует yt-dlp как "рубеж последней надежды", а не как основной путь
извлечения (основной путь — клиентский, без сервера).

Сервер не проксирует видео-трафик: отдаёт клиенту только метаданные и
прямые URL на googlevideo.com, дальше клиент качает сам.
"""
from __future__ import annotations

import json
import logging
import os

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

try:
    import redis
except ImportError:
    redis = None

import yt_dlp

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("kmep-backend")

app = FastAPI(title="KMEP Minimal Backend", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

_cache = None
if redis is not None:
    try:
        _cache = redis.Redis(
            host=os.getenv("REDIS_HOST", "localhost"),
            port=int(os.getenv("REDIS_PORT", "6379")),
            db=0,
            socket_connect_timeout=1,
        )
        _cache.ping()
    except Exception as e:
        log.warning("Redis unavailable, running without cache: %s", e)
        _cache = None


class ExtractRequest(BaseModel):
    video_id: str
    preferred_quality: str = "1080p"
    client_hint: str = "android_vr"


CACHE_TTL_SECONDS = 600


@app.get("/health")
async def health():
    return {"status": "ok", "cache": _cache is not None}


@app.post("/v1/extract")
async def extract_video(req: ExtractRequest):
    cache_key = f"kmep:{req.video_id}:{req.preferred_quality}"
    if _cache is not None:
        cached = _cache.get(cache_key)
        if cached:
            return json.loads(cached)

    height = "".join(ch for ch in req.preferred_quality if ch.isdigit()) or "1080"

    ydl_opts = {
        "format": f"bestvideo[height<={height}]+bestaudio/best[height<={height}]",
        "extractor_args": {
            "youtube": {
                "player_client": [req.client_hint],
                "player_skip": ["webpage", "configs"],
            }
        },
        "quiet": True,
        "no_warnings": True,
        "nocheckcertificate": True,
        "skip_download": True,
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(
                f"https://youtube.com/watch?v={req.video_id}", download=False
            )
    except yt_dlp.utils.DownloadError as e:
        raise HTTPException(status_code=502, detail=f"KMEP_UNAVAILABLE: {e}")
    except Exception as e:
        log.exception("Unexpected extraction failure")
        raise HTTPException(status_code=500, detail=f"KMEP_UNAVAILABLE: {e}")

    streams = [
        {
            "url": fmt["url"],
            "quality": fmt.get("format_note") or fmt.get("height") or "audio",
            "codec": fmt.get("vcodec") if fmt.get("vcodec") != "none" else fmt.get("acodec"),
            "type": "video" if fmt.get("vcodec") not in (None, "none") else "audio",
            "itag": fmt.get("format_id"),
            "width": fmt.get("width"),
            "height": fmt.get("height"),
            "bitrate": fmt.get("tbr"),
            "mimeType": fmt.get("ext"),
        }
        for fmt in info.get("formats", [])
        if fmt.get("url")
    ]

    result = {
        "status": "success",
        "source": "backend",
        "video": {
            "videoId": info.get("id"),
            "title": info.get("title"),
            "description": info.get("description", ""),
            "channelId": info.get("channel_id"),
            "channelName": info.get("channel"),
            "channelAvatar": info.get("channel_thumbnail"),
            "viewCount": info.get("view_count", 0),
            "duration": info.get("duration", 0),
            "isLive": info.get("is_live", False),
        },
        "streams": streams,
    }

    if _cache is not None:
        _cache.setex(cache_key, CACHE_TTL_SECONDS, json.dumps(result))

    return result


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
