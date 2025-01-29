import asyncio
import os
import shutil
import uuid
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional

from dotenv import load_dotenv
from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    Query,
    UploadFile,
)
from fastapi.responses import JSONResponse

# from firebase_admin import credentials, initialize_app, messaging
from pydantic import UUID4, BaseModel, EmailStr
from supabase import Client, create_client

from app.db.connection import supabase
from app.tasks import extract_faces_task

# # Initialize Firebase Admin SDK for FCM
# cred = credentials.Certificate("path/to/firebase-admin-sdk.json")
# firebase_app = initialize_app(cred)

load_dotenv()

UPLOAD_FOLDER = "app/uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

app = FastAPI(title="Photo Sharing Backend")

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif"}


class ShareStatus(str, Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"


class PhotoShare(BaseModel):
    photo_ids: List[UUID4]
    receiver_email: EmailStr


class PhotoResponse(BaseModel):
    id: UUID4
    filename: str
    public_url: str
    created_at: datetime


class ShareResponse(BaseModel):
    library_id: UUID4
    status: ShareStatus
    shared_photos: List[PhotoResponse]


async def get_current_user(authorization: str = Header(...)):
    try:
        # Verify JWT token with Supabase
        user = supabase.auth.get_user(authorization.split(" ")[1])
        return user
    except Exception as e:
        raise HTTPException(
            status_code=401, detail="Invalid authentication credentials"
        )


def allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


# async def send_push_notification(
#     fcm_token: str, title: str, body: str, data: Dict = None
# ):
#     try:
#         message = messaging.Message(
#             notification=messaging.Notification(
#                 title=title,
#                 body=body,
#             ),
#             data=data,
#             token=fcm_token,
#         )
#         response = messaging.send(message)
#         return response
#     except Exception as e:
#         print(f"Error sending push notification: {str(e)}")
#         return None


@app.post("/api/upload", response_model=List[PhotoResponse])
async def upload_photos(
    background_tasks: BackgroundTasks,
    files: List[UploadFile] = File(...),
):
    try:
        uploaded_photos = []
        for file in files:
            if file and allowed_file(file.filename):
                # Generate unique filename
                id = "a4c661ae-7e74-4902-ad7a-2c03de3781f5"
                photo_id = uuid.uuid4()
                ext = file.filename.rsplit(".", 1)[1].lower()
                storage_path = f"photos/{id}/{str(photo_id)}.{ext}"

                # Upload to Supabase Storage
                content = await file.read()
                result = supabase.storage.from_("photos").upload(storage_path, content)

                # Get public URL
                public_url = supabase.storage.from_("photos").get_public_url(
                    storage_path
                )
                file_path = os.path.join(UPLOAD_FOLDER, file.filename)
                with open(file_path, "wb") as buffer:
                    buffer.write(content)

                background_tasks.add_task(
                    extract_faces_task.delay,
                    file_path,
                    "a4c661ae-7e74-4902-ad7a-2c03de3781f5",
                )

                # Insert into photos table
                photo_data = {
                    "id": str(photo_id),
                    "filename": file.filename,
                    "storage_path": storage_path,
                    "public_url": public_url,
                    "owner_id": str(id),
                }
                result = supabase.table("photos").insert(photo_data).execute()

                uploaded_photos.append(PhotoResponse(**result.data[0]))

        return uploaded_photos

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/share", response_model=ShareResponse)
async def share_photos(share_data: PhotoShare, user=Depends(get_current_user)):
    try:
        # Get receiver's profile
        receiver = (
            supabase.table("profiles")
            .select("id, fcm_token")
            .eq("email", share_data.receiver_email)
            .single()
            .execute()
        )

        if not receiver.data:
            raise HTTPException(status_code=404, detail="Receiver not found")

        # Create shared library
        library_data = {
            "sender_id": user.id,
            "receiver_id": receiver.data["id"],
            "status": ShareStatus.PENDING,
        }
        library_result = (
            supabase.table("shared_libraries").insert(library_data).execute()
        )
        library_id = library_result.data[0]["id"]

        # Add photos to shared_photos
        shared_photos_data = [
            {"library_id": library_id, "photo_id": str(photo_id)}
            for photo_id in share_data.photo_ids
        ]

        supabase.table("shared_photos").insert(shared_photos_data).execute()

        # Get photo details
        photos_result = (
            supabase.table("photos")
            .select("*")
            .in_("id", [str(id) for id in share_data.photo_ids])
            .execute()
        )

        # Send push notification if FCM token exists
        # if receiver.data.get("fcm_token"):
        #     await send_push_notification(
        #         receiver.data["fcm_token"],
        #         "New Photo Library Shared",
        #         f"{user.email} has shared {len(share_data.photo_ids)} photos with you",
        #         {"type": "library_share", "library_id": str(library_id)},
        #     )

        return ShareResponse(
            library_id=library_id,
            status=ShareStatus.PENDING,
            shared_photos=[PhotoResponse(**photo) for photo in photos_result.data],
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/share/{library_id}/respond")
async def respond_to_share(
    library_id: UUID4, status: ShareStatus, user=Depends(get_current_user)
):
    try:
        # Update library status
        result = (
            supabase.table("shared_libraries")
            .update({"status": status})
            .eq("id", str(library_id))
            .eq("receiver_id", user.id)
            .execute()
        )

        if not result.data:
            raise HTTPException(status_code=404, detail="Shared library not found")

        # Get sender's FCM token
        sender = (
            supabase.table("profiles")
            .select("fcm_token")
            .eq("id", result.data[0]["sender_id"])
            .single()
            .execute()
        )

        # Send push notification to sender
        if sender.data and sender.data.get("fcm_token"):
            status_text = "accepted" if status == ShareStatus.ACCEPTED else "rejected"
            # await send_push_notification(
            #     sender.data["fcm_token"],
            #     f"Share {status_text}",
            #     f"{user.email} has {status_text} your shared photo library",
            #     {
            #         "type": "share_response",
            #         "library_id": str(library_id),
            #         "status": status,
            #     },
            # )

        return {"message": f"Share {status} successfully"}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/shared-with-me", response_model=List[ShareResponse])
async def get_shared_libraries(user=Depends(get_current_user)):
    try:
        result = (
            supabase.table("shared_libraries")
            .select("*", "shared_photos(photo(*))")
            .eq("receiver_id", user.id)
            .order("created_at", desc=True)
            .execute()
        )

        return [
            ShareResponse(
                library_id=library["id"],
                status=library["status"],
                shared_photos=[
                    PhotoResponse(**photo["photo"])
                    for photo in library["shared_photos"]
                ],
            )
            for library in result.data
        ]

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/fcm-token")
async def update_fcm_token(fcm_token: str = Form(...), user=Depends(get_current_user)):
    try:
        supabase.table("profiles").update({"fcm_token": fcm_token}).eq(
            "id", user.id
        ).execute()

        return {"message": "FCM token updated successfully"}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
