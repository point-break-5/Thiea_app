import os
import uuid

import matplotlib.pyplot as plt
import pandas as pd
from deepface import DeepFace
from PIL import Image

from app.celery_app import celery
from app.db.connection import supabase

EXTRACTED_FOLDER = "extracted_faces"
os.makedirs(EXTRACTED_FOLDER, exist_ok=True)

KNOWN_FACES_FOLDER = "known_faces"
os.makedirs(KNOWN_FACES_FOLDER, exist_ok=True)


@celery.task
def extract_faces_task(file_path: str, user_id: str, photo_id: str):
    try:
        os.makedirs(os.path.join(EXTRACTED_FOLDER, str(user_id)), exist_ok=True)
        response = supabase.table("faces").select("*").eq("user_id", user_id).execute()

        if response.data:
            os.makedirs(os.path.join(KNOWN_FACES_FOLDER, str(user_id)), exist_ok=True)
            for record in response.data:
                with open(
                    os.path.join(
                        KNOWN_FACES_FOLDER, str(user_id), f"{record['id']}.png"
                    ),
                    "wb",
                ) as f:
                    dl_response = supabase.storage.from_("faces").download(
                        record["storage_path"]
                    )
                    f.write(dl_response)

        if not response.data:
            result = DeepFace.extract_faces(
                file_path,
                detector_backend="retinaface",
                enforce_detection=False,
                align=True,
            )
            for face in result:
                face_id = uuid.uuid4()

                face_path = os.path.join(
                    EXTRACTED_FOLDER, str(user_id), f"{str(face_id)}.png"
                )
                plt.imsave(face_path, face["face"])
                storage_path = f"faces/{user_id}/{face_id}.png"
                with open(face_path, "rb") as f:
                    storage_response = supabase.storage.from_("faces").upload(
                        file=f,
                        path=storage_path,
                        file_options={"cache-control": "3600", "upsert": "false"},
                    )
                count = (
                    supabase.table("faces")
                    .select("*", count="exact")
                    .eq("user_id", user_id)
                    .execute()
                ).count
                insert_response = (
                    supabase.table("faces")
                    .insert(
                        {
                            "id": str(face_id),
                            "user_id": str(user_id),
                            "storage_path": storage_path,
                            "name": f"Person_{count + 1}",
                        }
                    )
                    .execute()
                )
                insert_response = (
                    supabase.table("photos_faces")
                    .insert(
                        {
                            "photo_id": str(photo_id),
                            "user_id": str(user_id),
                            "face_id": str(face_id),
                        }
                    )
                    .execute()
                )
        else:
            df = DeepFace.find(
                img_path=file_path,
                db_path=os.path.join(KNOWN_FACES_FOLDER, str(user_id)),
                model_name="Facenet",
                detector_backend="retinaface",
                enforce_detection=False,
                align=True,
                threshold=0.1,
                refresh_database=True,
            )
            if df[0].empty:
                result = DeepFace.extract_faces(
                    file_path,
                    detector_backend="retinaface",
                    enforce_detection=False,
                    align=True,
                )
                for face in result:
                    face_id = uuid.uuid4()

                    face_path = os.path.join(
                        EXTRACTED_FOLDER, str(user_id), f"{str(face_id)}.png"
                    )
                    plt.imsave(face_path, face["face"])
                    storage_path = f"faces/{user_id}/{face_id}.png"
                    with open(face_path, "rb") as f:
                        storage_response = supabase.storage.from_("faces").upload(
                            file=f,
                            path=storage_path,
                            file_options={"cache-control": "3600", "upsert": "false"},
                        )
                    count = (
                        supabase.table("faces")
                        .select("*", count="exact")
                        .eq("user_id", user_id)
                        .execute()
                    ).count
                    insert_response = (
                        supabase.table("faces")
                        .insert(
                            {
                                "id": str(face_id),
                                "user_id": str(user_id),
                                "storage_path": storage_path,
                                "name": f"Person_{count + 1}",
                            }
                        )
                        .execute()
                    )
                    insert_response = (
                        supabase.table("photos_faces")
                        .insert(
                            {
                                "photo_id": str(photo_id),
                                "user_id": str(user_id),
                                "face_id": str(face_id),
                            }
                        )
                        .execute()
                    )
            else:
                recog = df[0]
                recog = recog.reset_index(drop=True)  # Ensure index is sequential
                face_id = (
                    os.path.basename(recog.iloc[0]["identity"])
                    .split("/")[-1]
                    .split(".")[0]
                )
                insert_response = (
                    supabase.table("photos_faces")
                    .insert(
                        {
                            "photo_id": str(photo_id),
                            "user_id": str(user_id),
                            "face_id": face_id,
                        }
                    )
                    .execute()
                )
        return {"status": "success"}
    except Exception as e:
        # print(f"error: {e}")
        raise


if __name__ == "__main__":
    # DeepFace.find()
    extract_faces_task("app/uploads/img1.jpg", "a4c661ae-7e74-4902-ad7a-2c03de3781f5")
