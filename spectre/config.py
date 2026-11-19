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

    # Alpaca. Paper and live keys are separate at Alpaca; with paper keys real money is unreachable.
    # Leave the keys empty where a network proxy supplies them.
    alpaca_key_id: str = ""
    alpaca_secret_key: str = ""
    alpaca_trading_url: str = "https://paper-api.alpaca.markets"
    alpaca_data_url: str = "https://data.alpaca.markets"
    alpaca_stock_feed: str = "iex"  # free real-time feed; "sip" needs a paid plan
    alpaca_option_feed: str = "indicative"  # free; "opra" (full real-time) needs a paid plan
    # Cash only: refuse to send an order while the Alpaca account can borrow (margin multiplier above 1).
    alpaca_cash_only: bool = True
    # Brakes on the whole account. While it is this far below its high, or this far down on the
    # day, the bot buys nothing new; sales and stops carry on. 0 switches a brake off.
    trading_max_drawdown: float = 0.10
    trading_max_daily_loss: float = 0.03
    # X (Twitter). X charges for every post read, so it stays off until a daily budget of posts
    # is set; the reader never goes past it. The token can also be added by the hosting environment.
    x_daily_posts: int = 0
    x_cost_per_post: float = 0.005  # dollars; for the running estimate of what has been spent
    x_bearer_token: str = ""
    # What KAIROS weighs besides the crowd (signals/evidence.py). Each can be switched off.
    kairos_evidence: bool = True  # raise conviction for a name whose 6-12 month price trend is strong
    kairos_backdrop: bool = True  # make new stock and option purchases smaller while the market is turbulent
    # When set, the dashboard and API ask for this password (any user name). Required before
    # `spectre run` will listen on anything but this machine.
    dashboard_password: str = ""


settings = Settings()
