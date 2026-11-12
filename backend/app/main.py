from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .database import init_indexes
from .routers import admin as admin_router
from .routers import auth as auth_router
from .routers import logistics as logistics_router
from .routers import pmes as pmes_router
from .routers import production as production_router
from .routers import seminars as seminars_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_indexes()
    yield


app = FastAPI(title="Ugnay API", lifespan=lifespan)

# Open CORS for development (needed later for Flutter web). Restrict before deploying.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"],
                   allow_headers=["*"])

app.include_router(auth_router.router, prefix="/api/v1")
app.include_router(admin_router.router, prefix="/api/v1")
app.include_router(logistics_router.router, prefix="/api/v1")
app.include_router(production_router.router, prefix="/api/v1")
app.include_router(pmes_router.router, prefix="/api/v1")
app.include_router(seminars_router.admin_router, prefix="/api/v1")
app.include_router(seminars_router.member_router, prefix="/api/v1")


@app.get("/health")
def health():
    return {"status": "ok"} 