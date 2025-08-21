import time
from typing import Callable
from starlette.requests import Request
from starlette.responses import Response

async def log_request_timing(request: Request, call_next: Callable):
    t0 = time.time()
    try:
        resp: Response = await call_next(request)
        status = getattr(resp, "status_code", 0)
    except Exception:
        status = 500
        raise
    finally:
        dt = (time.time() - t0) * 1000.0
        path = request.url.path
        print(f"[api] {request.method} {path} -> {status} {dt:.1f}ms")
    return resp