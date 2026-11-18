from __future__ import annotations

import base64
import binascii
import secrets

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse
from sqlalchemy.engine import Engine

from spectre import __version__
from spectre.api.routers import (
    compliance,
    fundamentals,
    orders,
    portfolios,
    rates,
    risk,
    securities,
    signals,
    system,
)
from spectre.config import settings
from spectre.db import init_db, make_engine, make_session_factory
from spectre.trading.oms import OrderError


def create_app(database_url: str | None = None, engine: Engine | None = None) -> FastAPI:
    engine = engine or make_engine(database_url or settings.database_url)
    init_db(engine)

    app = FastAPI(
        title="SPECTRE",
        version=__version__,
        description="Portfolio, risk, compliance and order management on one shared book of record.",
    )
    app.state.engine = engine
    app.state.session_factory = make_session_factory(engine)

    @app.middleware("http")
    async def _password_gate(request: Request, call_next):
        """With SPECTRE_DASHBOARD_PASSWORD set, everything but the health check needs it
        (HTTP Basic, any user name). The API can create and execute orders, so it must not be
        reachable by strangers."""
        expected = settings.dashboard_password
        if not expected or request.url.path == "/health":
            return await call_next(request)
        supplied = ""
        scheme, _, token = request.headers.get("authorization", "").partition(" ")
        if scheme.lower() == "basic":
            try:
                supplied = base64.b64decode(token).decode("utf-8").partition(":")[2]
            except (binascii.Error, UnicodeDecodeError):
                supplied = ""
        if not secrets.compare_digest(supplied.encode(), expected.encode()):
            return PlainTextResponse("Password required", status_code=401,
                                     headers={"WWW-Authenticate": 'Basic realm="SPECTRE"'})
        return await call_next(request)

    @app.exception_handler(LookupError)
    async def _not_found(_: Request, exc: LookupError):
        return JSONResponse(status_code=404, content={"detail": str(exc)})

    @app.exception_handler(ValueError)
    async def _bad_request(_: Request, exc: ValueError):
        return JSONResponse(status_code=400, content={"detail": str(exc)})

    @app.exception_handler(OrderError)
    async def _order_error(_: Request, exc: OrderError):
        return JSONResponse(status_code=409, content={"detail": str(exc)})

    routers = (
        system.router, securities.router, portfolios.router, risk.router, risk.scenarios_router, compliance.router,
        orders.router, orders.trading_router, fundamentals.router, rates.router, signals.router,
        signals.dashboard_router,
    )
    for r in routers:
        app.include_router(r)
    return app


app = create_app()
