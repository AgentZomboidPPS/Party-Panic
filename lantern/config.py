from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Every field can be set with a LANTERN_ prefixed env var."""

    model_config = SettingsConfigDict(env_prefix="LANTERN_", env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./lantern.db"
    base_currency: str = "USD"

    # Risk defaults
    var_confidence: float = 0.99
    var_horizon_days: int = 1
    lookback_days: int = 500
    mc_simulations: int = 20_000
    mc_seed: int = 42


settings = Settings()
