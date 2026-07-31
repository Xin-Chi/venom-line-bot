FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Cloud Run 會用 PORT 環境變數告訴容器要監聽哪個 port
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}
