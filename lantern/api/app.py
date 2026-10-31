from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy.engine import Engine

from lantern import __version__
from lantern.api.routers import compliance, orders, portfolios, risk, securities, system
from lantern.config import settings
from lantern.db import init_db, make_engine, make_session_factory
from lantern.trading.oms import OrderError


def create_app(database_url: str | None = None, engine: Engine | None = None) -> FastAPI:
    engine = engine or make_engine(database_url or settings.database_url)
    init_db(engine)

    app = FastAPI(
        title="Lantern",
        version=__version__,
        description="Portfolio, risk, compliance and order management on one shared book of record.",
    )
    app.state.engine = engine
    app.state.session_factory = make_session_factory(engine)

    @app.exception_handler(LookupError)
    async def _not_found(_: Request, exc: LookupError):
        return JSONResponse(status_code=404, content={"detail": str(exc)})

    @app.exception_handler(ValueError)
    async def _bad_request(_: Request, exc: ValueError):
        return JSONResponse(status_code=400, content={"detail": str(exc)})

    @app.exception_handler(OrderError)
    async def _order_error(_: Request, exc: OrderError):
        return JSONResponse(status_code=409, content={"detail": str(exc)})

    for r in (system.router, securities.router, portfolios.router, risk.router, risk.scenarios_router,
              compliance.router, orders.router):
        app.include_router(r)
    return app


app = create_app()
