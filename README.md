# Featherless_Bipeds
This is our project repository for Android Application and Development Lab

## Virtual Environment Setup
```bash
python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt
```

## Populate the .env file
```
SUPABASE_URL=
SUPABASE_KEY=
```
Messenger e disi egula

## Run the Docker-Compose
```bash
docker-compose up -d
```

## Run Celery
```bash
celery -A app.tasks worker --loglevel=DEBUG
```

## Run the app
```bash
uvicorn app.main:app --reload
```