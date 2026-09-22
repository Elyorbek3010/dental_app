from fastapi import FastAPI

app = FastAPI(
    title="Dental Queue API",
    version="1.0.0",
)


@app.get("/api/health")
async def health_check():
    return {
        "status": "ok",
        "service": "Dental Queue API",
    }