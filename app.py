import os

# pyrefly: ignore [missing-import]
from dotenv import load_dotenv
load_dotenv()

from flask import Flask, jsonify, request
# pyrefly: ignore [missing-import]
from sqlalchemy import text

from models import Task, db

app = Flask(__name__)

DB_HOST = os.environ["DB_HOST"]
DB_PORT = os.environ["DB_PORT"]
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

app.config["SQLALCHEMY_DATABASE_URI"] = (
    f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db.init_app(app)

with app.app_context():
    db.create_all()


# Health / readiness
@app.get("/healthz")
def healthz():
    return "ok"


@app.get("/readyz")
def readyz():
    try:
        db.session.execute(text("SELECT 1"))
        return jsonify({"status": "ok"})
    except Exception as exc:
        return jsonify({"status": "error", "detail": str(exc)}), 503


# Tasks
@app.get("/tasks")
def list_tasks():
    tasks = Task.query.all()
    return jsonify([t.to_dict() for t in tasks])


@app.post("/tasks")
def create_task():
    body = request.get_json(force=True)
    if not body or not body.get("title"):
        return jsonify({"error": "title is required"}), 400
    task = Task(title=body["title"], done=bool(body.get("done", False)))
    db.session.add(task)
    db.session.commit()
    return jsonify(task.to_dict()), 201


@app.put("/tasks/<int:task_id>")
def update_task(task_id):
    task = db.session.get(Task, task_id)
    if task is None:
        return jsonify({"error": "not found"}), 404
    body = request.get_json(force=True)
    if "title" in body:
        task.title = body["title"]
    if "done" in body:
        task.done = bool(body["done"])
    db.session.commit()
    return jsonify(task.to_dict())


@app.delete("/tasks/<int:task_id>")
def delete_task(task_id):
    task = db.session.get(Task, task_id)
    if task is None:
        return jsonify({"error": "not found"}), 404
    db.session.delete(task)
    db.session.commit()
    return "", 204


if __name__ == "__main__":
    app.run(debug=True)
