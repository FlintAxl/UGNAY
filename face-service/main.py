from fastapi import FastAPI, File, HTTPException, UploadFile

from detector_embedder import FaceError, get_embedding

app = FastAPI(title="Ugnay Face Service")


@app.get("/")
def root():
    return {
        "service": "Ugnay Face Service",
        "status": "ok",
        "health": "/health",
        "docs": "/docs",
    }


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/face/embed")
async def embed(image: UploadFile = File(...)):
    data = await image.read()
    try:
        embedding = get_embedding(data)
    except FaceError as e:
        raise HTTPException(status_code=422, detail={"code": e.code, "message": e.message})
    return {"embedding": embedding, "dim": len(embedding)}