const taskForm = document.getElementById('taskForm');
const taskInput = document.getElementById('taskInput');
const taskList = document.getElementById('taskList');
const taskCount = document.getElementById('taskCount');
const emptyState = document.getElementById('emptyState');

// Load tasks from backend
async function loadTasks() {
    try {
        const res = await fetch('/tasks');
        const tasks = await res.json();
        renderTasks(tasks);
    } catch (err) {
        console.error('Failed to load tasks:', err);
    }
}

// Render task list into the DOM
function renderTasks(tasks) {
    taskList.innerHTML = '';

    if (!tasks || tasks.length === 0) {
        emptyState.style.display = 'block';
        taskCount.textContent = '0 tasks';
        return;
    }

    const sortedTasks = [...tasks].sort((a, b) => {
        // Incomplete tasks come first
        if (a.done !== b.done) {
            return a.done ? 1 : -1;
        }

        // Within each group, newest first
        return new Date(b.createdAt) - new Date(a.createdAt);
    });

    emptyState.style.display = 'none';
    const completedCount = sortedTasks.filter(t => t.done).length;
    taskCount.textContent = `${sortedTasks.length} task${sortedTasks.length === 1 ? '' : 's'} (${completedCount} completed)`;
    sortedTasks.forEach(task => {
        const li = document.createElement('li');
        li.className = `task-item ${task.done ? 'completed' : ''}`;
        li.dataset.id = task.id;

        const leftDiv = document.createElement('div');
        leftDiv.className = 'task-item-left';

        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.className = 'task-checkbox';
        checkbox.checked = task.done;
        checkbox.addEventListener('change', () => toggleTask(task.id, checkbox.checked));

        const span = document.createElement('span');
        span.className = 'task-title';
        span.textContent = task.title;

        leftDiv.appendChild(checkbox);
        leftDiv.appendChild(span);

        const deleteBtn = document.createElement('button');
        deleteBtn.className = 'btn-delete';
        deleteBtn.innerHTML = '&times;';
        deleteBtn.title = 'Delete task';
        deleteBtn.addEventListener('click', () => deleteTask(task.id));

        li.appendChild(leftDiv);
        li.appendChild(deleteBtn);
        taskList.appendChild(li);
    });
}

// Add a new task
taskForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const title = taskInput.value.trim();
    if (!title) return;

    try {
        const res = await fetch('/tasks', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ title })
        });

        if (res.ok) {
            taskInput.value = '';
            loadTasks();
        }
    } catch (err) {
        console.error('Failed to add task:', err);
    }
});

// Toggle task status
async function toggleTask(id, done) {
    try {
        await fetch(`/tasks/${id}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ done })
        });
        loadTasks();
    } catch (err) {
        console.error('Failed to update task:', err);
    }
}

// Delete a task
async function deleteTask(id) {
    try {
        const res = await fetch(`/tasks/${id}`, {
            method: 'DELETE'
        });
        if (res.ok) {
            loadTasks();
        }
    } catch (err) {
        console.error('Failed to delete task:', err);
    }
}

// Initial load
loadTasks();
