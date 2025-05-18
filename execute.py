import os
import subprocess
import ollama

# Define your fixed folder paths here
FOLDER_PATHS = {
    "home": "Home",
    "Documents": "Documents",
    "Downloads": "Downloads",
}

def read_transcription_file(filename="transcription.txt"):
    with open(filename, "r", encoding="utf-8") as file:
        return file.read().strip()

def get_command_from_ollama(transcription):
    prompt = (
        f"'{transcription}'\n"
        "Use these exact paths if folders are mentioned:\n"
        "home :/Users/prateek/Desktop\n"
        "documents : /Users/prateek/Documents\n"
        "downloads : /Users/prateek/Downloads\n"
        "Only return the command with no extra output, no markdown, no quotes around the command."
        "ensure that during move and other commands file extension is specified as given in the command if text file is said in transciption then add .txt, .cpp, .pdf, .png, .jpg, .mkv, and make sure it.. "
        "when i am saying delete the content don't delete full file just delete the content."
        "if the transciption is right i am taking about write"
        "If it's a GitHub command:\n"
        "- My GitHub username is Ragnarok04\n"
        "- My email is prateekrathi0410@gmail.com\n"
        "- Use SSH URLs only (git@github.com:...)\n"
        "- Do NOT use https:// in Git commands\n"
        "- SSH = SHA256:dNm3vWzZ5D/5cpHq7zpsnZuoZ4U3qIn1knNwc+xhxYM\n"
        "- Do NOT include any SSH key flags like --key or anything else\n"
        "- Use commands like: git add ., git commit -m '...', git push origin main\n"
        "- The repository for this project is: git@github.com:Ragnarok04/flutter_application_2.git"
        "- The default branch name is 'main', NOT 'master'."
        )

    response = ollama.chat(
        model="llama3",
        messages=[{"role": "user", "content": prompt}]
    )

    command = response['message']['content'].strip().strip('`')
    return command

def replace_paths(command):
    for folder, full_path in FOLDER_PATHS.items():
        command = command.replace(f"{folder}\\", f"{full_path}\\")
        command = command.replace(f"{folder}/", f"{full_path}/")
    return command


def setup_ssh_agent():
    # 1) start ssh-agent and capture its output
    print("Starting ssh-agent…")
    proc = subprocess.run(
        ['ssh-agent', '-s'], 
        shell=False, 
        capture_output=True, 
        text=True
    )
    if proc.returncode != 0:
        print("Failed to start ssh-agent")
        return False

    # 2) parse and export SSH_AGENT_PID and SSH_AUTH_SOCK
    for line in proc.stdout.splitlines():
        if line.startswith("SSH_"):
            # e.g. "SSH_AUTH_SOCK=/tmp/ssh-XYZ; export SSH_AUTH_SOCK;"
            pair = line.split(';')[0]
            k, v = pair.split('=', 1)
            os.environ[k] = v

    # 3) look for either id_rsa or id_ed25519
    home = os.path.expanduser("~")
    candidates = [
        os.path.join(home, ".ssh", "id_rsa"),
        os.path.join(home, ".ssh", "id_ed25519")
    ]
    keyfile = next((k for k in candidates if os.path.exists(k)), None)
    if not keyfile:
        print("No SSH key found in ~/.ssh (tried id_rsa and id_ed25519).")
        return False

    # 4) add it to the agent
    print(f"Adding SSH key: {keyfile}")
    add = subprocess.run(
        ['ssh-add', keyfile], 
        capture_output=True, 
        text=True
    )
    if add.returncode != 0:
        print("Error adding SSH key:", add.stderr.strip())
        return False

    print("SSH key added successfully.")
    return True


def execute_command(command):
    print(f"Executing: {command}")
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        if result.stdout:
            print("Output:\n" + result.stdout)
        if result.stderr:
            print("Error:\n" + result.stderr)
    except Exception as e:
        print(f"Execution failed: {e}")

if __name__ == "__main__":
    transcription = read_transcription_file("transcription.txt")
    print(f"Transcription: {transcription}")

    try:
        command = get_command_from_ollama(transcription)
        command = replace_paths(command)
        print(f"Generated Command: {command}")

        with open("command.txt", "w", encoding="utf-8") as file:
            file.write(command)

        if setup_ssh_agent():
            execute_command(command)
        else:
            print("SSH agent setup failed. Command not executed.")
    except Exception as e:
        print(f"Error: {e}")
