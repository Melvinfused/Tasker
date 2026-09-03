# Tasker 📝

A lightweight Flask REST API for task management powered by PostgreSQL and SQLAlchemy.

---

## 🚀 Features

- **Health Checks**: `/healthz` (service liveness) and `/readyz` (database connectivity).
- **CRUD Operations**: Create, read, update, and delete tasks.
- **Auto Table Creation**: Tables are automatically created on startup via `db.create_all()`.

---

## 🛠️ Prerequisites

- **Python 3.10+**
- **PostgreSQL** running locally or remotely with a database created (e.g., `tasker`).

---

## 📦 Setup & Installation

### 1. Clone the repository
```bash
git clone https://github.com/Melvinfused/Tasker.git
cd Tasker
```

### 2. Create and activate a virtual environment
- **Windows (PowerShell):**
  ```powershell
  python -m venv venv
  venv\Scripts\activate
  ```
- **macOS / Linux:**
  ```bash
  python3 -m venv venv
  source venv/bin/activate
  ```

### 3. Install dependencies
```bash
pip install -r requirements.txt
```

### 4. Configure Environment Variables
Create a `.env` file in the project root:

```ini
DB_HOST=localhost
DB_PORT=5432
DB_NAME=tasker
DB_USER=postgres
DB_PASSWORD=your_postgres_password

FLASK_APP=app.py
```

> **Note:** Ensure the database exists in PostgreSQL before launching:
> ```sql
> CREATE DATABASE tasker;
> ```

---

## 🏃 Running the Application

### Development mode:
```powershell
python app.py
```
The server will start at `http://127.0.0.1:5000`.

---

## 📡 API Reference & Quick Testing

### 1. Liveness Probe
Checks if the web server is responsive.
- **Method:** `GET /healthz`
- **Request:**
  ```powershell
  curl http://127.0.0.1:5000/healthz
  ```
- **Response:** `ok` (Status 200)

---

### 2. Readiness Probe
Verifies database connectivity (`SELECT 1`). Returns `503` if the database is unreachable.
- **Method:** `GET /readyz`
- **Request:**
  ```powershell
  curl http://127.0.0.1:5000/readyz
  ```
- **Response:**
  ```json
  {"status": "ok"}
  ```

---

### 3. List All Tasks
Fetches all stored tasks.
- **Method:** `GET /tasks`
- **Request:**
  ```powershell
  curl http://127.0.0.1:5000/tasks
  ```
- **Response:**
  ```json
  [
    {
      "id": 1,
      "title": "Setup PostgreSQL database",
      "done": false
    }
  ]
  ```

---

### 4. Create a Task
Adds a new task. `title` is required; `done` defaults to `false`.
- **Method:** `POST /tasks`
- **Request:**
  ```powershell
  curl -X POST http://127.0.0.1:5000/tasks -H "Content-Type: application/json" -d '{"title": "Buy groceries"}'
  ```
- **Response:** `201 Created`
  ```json
  {
    "id": 1,
    "title": "Buy groceries",
    "done": false
  }
  ```

---

### 5. Update a Task
Updates `title` and/or completion status `done`.
- **Method:** `PUT /tasks/<id>`
- **Request:**
  ```powershell
  curl -X PUT http://127.0.0.1:5000/tasks/1 -H "Content-Type: application/json" -d '{"title": "Buy groceries", "done": true}'
  ```
- **Response:** `200 OK`
  ```json
  {
    "id": 1,
    "title": "Buy groceries",
    "done": true
  }
  ```

---

### 6. Delete a Task
Removes a task by its ID.
- **Method:** `DELETE /tasks/<id>`
- **Request:**
  ```powershell
  curl -X DELETE http://127.0.0.1:5000/tasks/1
  ```
- **Response:** `204 No Content`

---

## 📂 Project Structure

```text
tasker/
├── .env                # Environment variables (ignored by git)
├── .gitignore          # Git exclusion rules
├── app.py              # Main Flask application & routes
├── models.py           # SQLAlchemy Task model
├── requirements.txt    # Python dependencies
└── README.md           # Documentation
```
