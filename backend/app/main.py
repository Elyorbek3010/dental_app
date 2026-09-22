from fastapi import FastAPI
from sqlalchemy import text

from app.api.auth import router as auth_router
from app.api.catalog import router as catalog_router
from app.api.queues import router as queues_router
from app.db.session import engine

app = FastAPI(
    title="Dental Queue API",
    version="1.0.0",
)

app.include_router(auth_router)
app.include_router(catalog_router)
app.include_router(queues_router)


@app.get("/api/health")
async def health_check():
    return {
        "status": "ok",
        "service": "Dental Queue API",
    }


@app.get("/api/health/db")
def database_health_check():
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))

    return {
        "status": "ok",
        "database": "connected",
    }