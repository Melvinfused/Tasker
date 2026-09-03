# Tasker

Simple Flask REST API for managing tasks with PostgreSQL and SQLAlchemy.

## Requirements

- Python 3.10+
- PostgreSQL

## Setup

1. Clone and enter the repo:
   ```bash
   git clone https://github.com/Melvinfused/Tasker.git
   cd Tasker
   ```

2. Create and activate virtual environment:
   ```bash
   python -m venv venv
   venv\Scripts\activate   # Windows
   # source venv/bin/activate  # Linux/macOS
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Create `.env` in the root:
   ```env
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=your_db_name
   DB_USER=your_db_user
   DB_PASSWORD=your_db_password
   ```

Make sure the database exists in postgres (`CREATE DATABASE your_db_name;`).

## Running

```bash
python app.py
```

Runs by default on `http://127.0.0.1:5000`. Tables are created automatically on startup.

## Endpoints

| Method | Route | Description |
|---|---|---|
| `GET` | `/` | Web UI (HTML/CSS frontend) |
| `GET` | `/healthz` | App health check (returns `ok`) |
| `GET` | `/readyz` | DB connectivity check (returns 503 if down) |
| `GET` | `/tasks` | List all tasks |
| `POST` | `/tasks` | Create task (`{"title": "..."}`) |
| `PUT` | `/tasks/<id>` | Update task (`{"title": "...", "done": true}`) |
| `DELETE` | `/tasks/<id>` | Delete task |

### Examples

**Create a task:**
```bash
curl -X POST http://127.0.0.1:5000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "test task"}'
```

**Get all tasks:**
```bash
curl http://127.0.0.1:5000/tasks
```

**Update a task:**
```bash
curl -X PUT http://127.0.0.1:5000/tasks/1 \
  -H "Content-Type: application/json" \
  -d '{"done": true}'
```

**Delete a task:**
```bash
curl -X DELETE http://127.0.0.1:5000/tasks/1
```
