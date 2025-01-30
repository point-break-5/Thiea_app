from celery import Celery

celery = Celery("tasks", broker="pyamqp://guest@rabbitmq//")
