from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
import os, shutil, base64, tempfile
import whisper, ollama

app = Flask(__name__)
CORS(app)

# -- File management endpoints --
FOLDER_MAPPING = {
     "home": "/Users/prateek/Desktop",
    "documents": "/Users/prateek/Documents",
    "downloads": "/Users/prateek/Downloads"
}
def build_folder_tree(path):
    items = []
    try:
        for entry in os.scandir(path):
            full_path = os.path.join(path, entry.name)
            if entry.is_dir():
                items.append({
                    "name": entry.name,
                    "type": "folder",
                    "children": build_folder_tree(full_path)
                })
            else:
                items.append({
                    "name": entry.name,
                    "type": "file"
                })
    except Exception as e:
        print(f"Error reading {path}: {e}")
    return items


@app.route('/get_structure', methods=['GET'])
def get_structure():
    key = request.args.get('path', 'home').lower()
    base_path = FOLDER_MAPPING.get(key, key)

    if not os.path.exists(base_path):
        return jsonify({"error": "Path not found"}), 404

    return jsonify({
        "name": os.path.basename(base_path) or key,
        "type": "folder",
        "children": build_folder_tree(base_path)
    })

@app.route('/files', methods=['GET'])
def list_files():
    key = request.args.get('path', 'home').lower()
    path = FOLDER_MAPPING.get(key, key)
    try:
        items = []
        for name in os.listdir(path):
            full = os.path.join(path, name)
            items.append({
                "name": name,
                "path": full.replace("\\", "/"),
                "is_dir": os.path.isdir(full)
            })
        return jsonify(items)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/file-content', methods=['GET'])
def file_content():
    p = request.args.get('path', '').replace("\\", "/")
    parts = p.split('/', 1)
    base_folder = parts[0].lower()
    relative_path = parts[1] if len(parts) > 1 else ''

    base_path = FOLDER_MAPPING.get(base_folder, None)

    if base_path:
        base_folder_name = os.path.basename(base_path)  # e.g. "Desktop"
        if relative_path.startswith(base_folder_name):
            relative_path = relative_path[len(base_folder_name)+1:]
        p = os.path.join(base_path, relative_path)
    else:
        return jsonify({"error": "Invalid base folder"}), 404

    print(f"✅ Mapped path to absolute: {p}")

    if not os.path.exists(p): 
        print("❌ File not found")
        return jsonify({"error": "Not found"}), 404
    if os.path.isdir(p): 
        print("❌ Path is a directory, not a file")
        return jsonify({"error": "Is a directory"}), 400

    return send_file(p, as_attachment=False)





@app.route('/delete-file', methods=['POST'])
def delete_file():
    data = request.json or {}
    p = data.get('path', '').replace("\\", "/")
    if not os.path.exists(p): return jsonify({"error": "Not found"}), 404
    try:
        if os.path.isdir(p): shutil.rmtree(p)
        else: os.remove(p)
        return jsonify({"message": "Deleted"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/rename-file', methods=['POST'])
def rename_file():
    d = request.json or {}
    old = d.get('path', '').replace("\\", "/")
    new = d.get('newName', '')
    if not os.path.exists(old): return jsonify({"error": "Not found"}), 404
    try:
        dst = os.path.join(os.path.dirname(old), new)
        os.rename(old, dst)
        return jsonify({"message": "Renamed", "newPath": dst.replace("\\", "/")})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/add-file', methods=['POST'])
def add_file():
    d = request.json or {}
    folder = d.get('folder', '').lower()
    name = d.get('name', '')
    content = d.get('content', '')
    ftype = d.get('type', 'text')
    base = FOLDER_MAPPING.get(folder, folder)
    path = os.path.join(base, name)
    try:
        if ftype == 'binary':
            data = base64.b64decode(content)
            with open(path, 'wb') as f: f.write(data)
        else:
            with open(path, 'w', encoding='utf-8') as f: f.write(content)
        return jsonify({"message": "Added", "path": path.replace("\\", "/")})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# -- Voice → LLM → Shell endpoint --
WHISPER = whisper.load_model("base")
OLLAMA_MODEL = "llama3"

def text_to_command(text: str) -> str:
    prompt = (
        "Convert the following user request into a Linux terminal command:\n"
        f"'{text}'\n"
        "Only return the command without any explanations."
    )
    resp = ollama.chat(
        model=OLLAMA_MODEL,
        messages=[{"role": "user", "content": prompt}]
    )
    return resp["message"]["content"].strip()

@app.route('/execute-text', methods=['POST'])
def execute_text():
    data = request.json or {}
    txt = data.get('text', '').strip()
    if not txt: return jsonify({"error": "No text"}), 400

    try:
        cmd = text_to_command(txt)
        tmp = tempfile.gettempdir() + "/_voice_out.txt"
        code = os.system(f"{cmd} 2>&1 | tee {tmp}")
        with open(tmp) as f: out = f.read()
        return jsonify({
            "transcription": txt,
            "command": cmd,
            "exit_code": code,
            "output": out
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# New imports for recording & command execution
import subprocess

# Endpoint: record audio & generate transcription
@app.route('/transcribe', methods=['GET'])
def transcribe_route():
    try:
        # Call external script to record and transcribe
        subprocess.run(["python3", "demmo.py"], check=True)
        # Read the resulting transcription
        with open("transcription.txt", "r", encoding="utf-8") as f:
            transcription = f.read().strip()
        return jsonify({"transcription": transcription})
    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Transcription failed: {e}"}), 500

# Endpoint: execute command from transcription via Ollama
@app.route('/execute-transcription', methods=['GET'])
def execute_transcription_route():
    try:
        # Call external script to convert transcription to command and execute
        subprocess.run(["python3", "execute.py"], check=True)
        # Read the generated command and optionally return it
        with open("command.txt", "r", encoding="utf-8") as f:
            command = f.read().strip()
        return jsonify({"command": command, "status": "executed"})
    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Execution failed: {e}"}), 500

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=8000, debug=True)
