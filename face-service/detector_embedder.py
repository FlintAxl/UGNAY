"""Detect one face in an image and return a 512-D L2-normalized embedding."""
import cv2
import numpy as np
from insightface.app import FaceAnalysis

MIN_FACE_SIZE = 80      # pixels (width and height of the face box)
MIN_DET_SCORE = 0.6     # detector confidence

_app = None


class FaceError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def _get_app() -> FaceAnalysis:
    """Load the model once. buffalo_s = small detector + MobileFaceNet (512-D)."""
    global _app
    if _app is None:
        _app = FaceAnalysis(
            name="buffalo_s",
            providers=["CPUExecutionProvider"],
            allowed_modules=["detection", "recognition"],
        )
        _app.prepare(ctx_id=-1, det_size=(640, 640))
    return _app


def get_embedding(image_bytes: bytes) -> list[float]:
    img = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise FaceError("INVALID_IMAGE", "Could not read the image.")

    faces = _get_app().get(img)
    if len(faces) == 0:
        raise FaceError("NO_FACE", "No face detected. Face the camera in good light.")
    if len(faces) > 1:
        raise FaceError("MULTIPLE_FACES", "More than one face detected.")

    face = faces[0]
    x1, y1, x2, y2 = face.bbox
    if min(x2 - x1, y2 - y1) < MIN_FACE_SIZE:
        raise FaceError("FACE_TOO_SMALL", "Face is too small. Move closer.")
    if face.det_score < MIN_DET_SCORE:
        raise FaceError("LOW_QUALITY", "Face is unclear. Improve lighting and retry.")

    return face.normed_embedding.tolist()


def cosine_similarity(a, b) -> float:
    a, b = np.asarray(a, dtype=np.float32), np.asarray(b, dtype=np.float32)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))