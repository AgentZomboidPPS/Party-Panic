from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Every field can be set with a SPECTRE_ prefixed env var."""

    model_config = SettingsConfigDict(env_prefix="SPECTRE_", env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./spectre.db"
    base_currency: str = "USD"

    # Risk defaults
    var_confidence: float = 0.99
    var_horizon_days: int = 1
    lookback_days: int = 500
    mc_simulations: int = 20_000
    mc_seed: int = 42

    # Execution guardrails. Defaults are deliberately small; "live" must be chosen explicitly.
    trading_mode: str = "paper"  # "paper" or "live"
    trading_max_order_notional: float = 1_000.0
    trading_max_daily_notional: float = 5_000.0
    trading_max_orders_per_day: int = 20
    trading_max_position_weight: float = 0.20
    trading_require_approval: bool = True  # live orders wait for a named person to approve each one
    trading_allowed_symbols: str = ""  # comma list; empty means any security in the book

    # The SEC answers only tools that identify themselves: "Name contact@example.com".
    # Set SPECTRE_SEC_USER_AGENT yourself (environment or .env); it is never stored in the code.
    sec_user_agent: str = ""


settings = Settings()
