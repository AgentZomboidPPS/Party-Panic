from __future__ import annotations

from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool


class Base(DeclarativeBase):
    pass


def make_engine(url: str) -> Engine:
    kwargs: dict = {}
    if url.startswith("sqlite"):
        kwargs["connect_args"] = {"check_same_thread": False}
        if url in ("sqlite://", "sqlite:///:memory:"):
            # One shared connection so an in-memory DB survives across sessions.
            kwargs["poolclass"] = StaticPool
    engine = create_engine(url, **kwargs)
    if url.startswith("sqlite"):

        @event.listens_for(engine, "connect")
        def _enable_fk(dbapi_conn, _record):
            cur = dbapi_conn.cursor()
            cur.execute("PRAGMA foreign_keys=ON")
            cur.close()

    return engine


def make_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, expire_on_commit=False)


def init_db(engine: Engine) -> None:
    import spectre.execution.models  # noqa: F401
    import spectre.fundamentals.models  # noqa: F401
    import spectre.models  # noqa: F401  (registers tables on Base.metadata)
    import spectre.rates.models  # noqa: F401
    import spectre.signals.models  # noqa: F401

    Base.metadata.create_all(engine)
    _add_missing_columns(engine)


def _add_missing_columns(engine: Engine) -> None:
    """A database made by an older version keeps working: columns added since are created in
    place. Only additions are handled (nullable, or with a default); nothing is dropped or
    retyped, so this is safe to run on every start."""
    inspector = inspect(engine)
    with engine.begin() as conn:
        for table in Base.metadata.sorted_tables:
            have = {c["name"] for c in inspector.get_columns(table.name)}
            for column in table.columns:
                if column.name in have:
                    continue
                ddl = f"ALTER TABLE {table.name} ADD COLUMN {column.name} {column.type.compile(engine.dialect)}"
                if column.server_default is not None:
                    ddl += f" DEFAULT '{column.server_default.arg}' NOT NULL"
                elif not column.nullable:
                    raise RuntimeError(f"{table.name}.{column.name} is new and required but has no server default")
                conn.execute(text(ddl))
