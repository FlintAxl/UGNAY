"""
Test similarity scores to choose your threshold.

Two photos:
    python compare_faces.py me1.jpg me2.jpg

A folder (one subfolder per person, several photos each):
    photos/
      juan/ a.jpg b.jpg c.jpg
      maria/ a.jpg b.jpg
    python compare_faces.py photos
"""
import itertools
import sys
from pathlib import Path

import numpy as np

from detector_embedder import FaceError, cosine_similarity, get_embedding

EXTS = {".jpg", ".jpeg", ".png"}


def embed_file(path: Path):
    try:
        return get_embedding(path.read_bytes())
    except FaceError as e:
        print(f"  skipped {path.name}: {e.code}")
        return None


def compare_two(a: str, b: str):
    ea, eb = embed_file(Path(a)), embed_file(Path(b))
    if ea and eb:
        print(f"Similarity: {cosine_similarity(ea, eb):.4f}")


def compare_folder(root: str):
    people = {}
    for person_dir in sorted(p for p in Path(root).iterdir() if p.is_dir()):
        embs = [e for f in sorted(person_dir.iterdir())
                if f.suffix.lower() in EXTS and (e := embed_file(f))]
        if embs:
            people[person_dir.name] = embs

    same, diff = [], []
    for embs in people.values():
        same += [cosine_similarity(a, b) for a, b in itertools.combinations(embs, 2)]
    for (_, ea), (_, eb) in itertools.combinations(people.items(), 2):
        diff += [cosine_similarity(a, b) for a in ea for b in eb]

    def stats(name, scores):
        if scores:
            print(f"{name}: n={len(scores)} min={min(scores):.3f} "
                  f"mean={np.mean(scores):.3f} max={max(scores):.3f}")
        else:
            print(f"{name}: no pairs")

    stats("Same person     ", same)
    stats("Different people", diff)
    if same and diff:
        print(f"\nGap check: lowest same-person ({min(same):.3f}) "
              f"vs highest different-person ({max(diff):.3f})")
        for t in (0.3, 0.4, 0.5, 0.6):
            frr = sum(s < t for s in same) / len(same) * 100
            far = sum(s >= t for s in diff) / len(diff) * 100
            print(f"threshold {t}: false reject {frr:.1f}% | false accept {far:.1f}%")


if __name__ == "__main__":
    if len(sys.argv) == 3:
        compare_two(sys.argv[1], sys.argv[2])
    elif len(sys.argv) == 2:
        compare_folder(sys.argv[1])
    else:
        print(__doc__)