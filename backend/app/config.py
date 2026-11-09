from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    database_url: str = "postgresql+psycopg2://kanha:kanha@localhost:5432/kanha"
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str = "change-me"
    access_minutes: int = 30
    refresh_days: int = 30
    dev_otp_echo: bool = True          # returns the OTP in the API response; turn OFF in production
    auto_create_tables: bool = True    # set False once you use Alembic
    cors_origins: str = "http://localhost:5173"
    s3_endpoint: str = "http://localhost:9000"        # internal (API -> storage); empty for AWS S3
    s3_public_endpoint: str = "http://localhost:9000"  # what phones/browsers can reach
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_bucket: str = "kanha-photos"
    s3_region: str = "ap-south-1"
    max_photo_bytes: int = 6_000_000
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    mail_from: str = "kanha-qr@megaminds.local"
    lab_email: str = "lab@example.com"


settings = Settings()
