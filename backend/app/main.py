import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text

from app.api.admin import router as admin_router
from app.api.auth import router as auth_router
from app.api.catalog import router as catalog_router
from app.api.notifications import router as notifications_router
from app.api.public import router as public_router
from app.api.queues import router as queues_router
from app.db.session import engine
from app.services.smart_call_timer import run_smart_call_timer_loop

from fastapi.middleware.cors import CORSMiddleware


@asynccontextmanager
async def lifespan(_app: FastAPI):
    stop_event = asyncio.Event()
    timer_task = asyncio.create_task(run_smart_call_timer_loop(stop_event))
    try:
        yield
    finally:
        stop_event.set()
        timer_task.cancel()
        try:
            await timer_task
        except asyncio.CancelledError:
            pass


app = FastAPI(
    title="Dental Queue API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(catalog_router)
app.include_router(queues_router)
app.include_router(public_router)
app.include_router(notifications_router)
app.include_router(admin_router)


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