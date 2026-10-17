from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DB_URI: str
    DATABASE_NAME: str = "Ugnay"

    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    FACE_CHALLENGE_EXPIRE_MINUTES: int = 5

    CLOUDINARY_CLOUD_NAME: str
    CLOUDINARY_API_KEY: str
    CLOUDINARY_API_SECRET: str
    CLOUDINARY_UPLOAD_FOLDER: str = "ugnay"

    FACE_SERVICE_URL: str = "http://localhost:8001"
    FACE_THRESHOLD: float = 0.4
    AI_SERVICE_URL: str = "http://localhost:8002"


settings = Settings()