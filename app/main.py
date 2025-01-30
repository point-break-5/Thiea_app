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
    WebSocket,
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

FIXED_USER_ID = "a4c661ae-7e74-4902-ad7a-2c03de3781f5"


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


class UploadResponse(BaseModel):
    photo_id: UUID4
    public_url: str
    status: str


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
                id = "5be7e8dc-dd94-45a9-9552-1e04b65ca12e"
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
                    "5be7e8dc-dd94-45a9-9552-1e04b65ca12e",
                    str(photo_id),
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


@app.get("/")
async def root():
    return {"message": "Photo Sharing API is running"}


@app.post("/api/upload-and-share", response_model=List[UploadResponse])
async def upload_and_share(
    files: List[UploadFile] = File(...), receiver_email: str = Form(...)
):
    uploaded_photos = []

    try:
        receiver_user_data = {
            "id": str(uuid.uuid4()),
            "email": receiver_email,
            "created_at": datetime.utcnow().isoformat(),
        }

        existing_user = (
            supabase.table("profiles")
            .select("id")
            .eq("email", receiver_email)
            .execute()
        )

        if existing_user.data:
            receiver_id = existing_user.data[0]["id"]
        else:
            new_user = supabase.table("profiles").insert(receiver_user_data).execute()
            receiver_id = new_user.data[0]["id"]

        print(f"Receiver ID: {receiver_id}")

        for file in files:
            try:
                ext = file.filename.rsplit(".", 1)[1].lower()
                photo_id = uuid.uuid4()
                storage_path = f"photos/{photo_id}.{ext}"

                print(f"Processing file: {file.filename}")

                content = await file.read()

                print("Uploading to storage...")
                storage_response = supabase.storage.from_("photos").upload(
                    path=storage_path,
                    file=content,
                    file_options={"content-type": file.content_type},
                )
                print(f"Storage response: {storage_response}")

                public_url = supabase.storage.from_("photos").get_public_url(
                    storage_path
                )
                print(f"Public URL: {public_url}")

                photo_data = {
                    "id": str(photo_id),
                    "filename": file.filename,
                    "storage_path": storage_path,
                    "public_url": public_url,
                    "owner_id": FIXED_USER_ID,
                    "created_at": datetime.utcnow().isoformat(),
                }

                print("Inserting into photos table...")
                photo_result = supabase.table("photos").insert(photo_data).execute()
                print(f"Photo insert result: {photo_result.data}")

                uploaded_photos.append(
                    UploadResponse(
                        photo_id=photo_id, public_url=public_url, status="uploaded"
                    )
                )

            except Exception as e:
                print(f"Error processing file {file.filename}: {str(e)}")
                print(f"Full error details: {e.__class__.__name__}")
                continue

        if uploaded_photos:
            try:
                library_data = {
                    "id": str(uuid.uuid4()),
                    "sender_id": FIXED_USER_ID,
                    "receiver_id": receiver_id,
                    "status": "pending",
                    "created_at": datetime.utcnow().isoformat(),
                }

                print("Creating shared library entry...")
                library_result = (
                    supabase.table("shared_libraries").insert(library_data).execute()
                )
                print(f"Library creation result: {library_result.data}")

                library_id = library_result.data[0]["id"]

                print("Creating shared photos entries...")
                for photo in uploaded_photos:
                    shared_photo_data = {
                        "id": str(uuid.uuid4()),
                        "library_id": library_id,
                        "photo_id": str(photo.photo_id),
                        "created_at": datetime.utcnow().isoformat(),
                    }

                    shared_photo_result = (
                        supabase.table("shared_photos")
                        .insert(shared_photo_data)
                        .execute()
                    )
                    print(f"Shared photo insert result: {shared_photo_result.data}")

            except Exception as e:
                print(f"Error creating library: {str(e)}")
                print(f"Full error details: {e.__class__.__name__}")
                raise HTTPException(status_code=500, detail=str(e))

        return uploaded_photos

    except Exception as e:
        print(f"Upload error: {str(e)}")
        print(f"Full error details: {e.__class__.__name__}")
        raise HTTPException(status_code=500, detail=str(e))


@app.websocket("/ws/library-updates/{user_id}")
async def library_updates_websocket(websocket: WebSocket, user_id: str):
    try:
        await websocket.accept()
        print(f"WebSocket connection accepted for user: {user_id}")

        subscription = (
            supabase.table("shared_libraries")
            .on("INSERT", lambda payload: handle_library_update(payload, websocket))
            .subscribe()
        )

        print(f"Subscribed to shared libraries updates for user: {user_id}")

        while True:
            try:
                data = await websocket.receive_text()
                if data == "ping":
                    await websocket.send_text("pong")
            except Exception as e:
                print(f"Error in WebSocket loop: {str(e)}")
                break

    except Exception as e:
        print(f"WebSocket error: {str(e)}")
    finally:
        if "subscription" in locals():
            try:
                await subscription.unsubscribe()
            except Exception as e:
                print(f"Error unsubscribing: {str(e)}")
        try:
            await websocket.close()
        except Exception as e:
            print(f"Error closing websocket: {str(e)}")
        print(f"WebSocket connection closed for user: {user_id}")


async def handle_library_update(payload, websocket: WebSocket):
    try:
        library_id = payload["new"]["id"]
        print(f"Handling library update for library: {library_id}")

        photos_result = (
            supabase.table("shared_photos")
            .select("*")
            .eq("library_id", library_id)
            .execute()
        )

        await websocket.send_json(
            {
                "type": "library_update",
                "library_id": library_id,
                "photos": photos_result.data,
            }
        )

        print(f"Sent library update for library: {library_id}")

    except Exception as e:
        print(f"Error handling library update: {str(e)}")


@app.get("/health")
async def health_check():
    try:
        test_query = supabase.table("photos").select("count", count="exact").execute()
        return {
            "status": "healthy",
            "database": "connected",
            "timestamp": datetime.utcnow().isoformat(),
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Service unhealthy: {str(e)}")


if __name__ == "__main__":
    print("Starting Photo Sharing API...")
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
