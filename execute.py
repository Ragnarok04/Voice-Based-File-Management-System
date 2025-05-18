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
        "- Username: Ragnarok04\n"
        "- Email: prateekrathi0410@gmail.com\n"
        "- Use SSH (SHA256:IK+lzexpDuDg2ciD/UVrvwdBt6MNNiX3b8mW101nxAo)\n"
        "- DO NOT include --key or SSH key flags in the command\n"
        "- Use simple git commands like: git add ., git commit -m '...', git push origin main\n"
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

        execute_command(command)
    except Exception as e:
        print(f"Error: {e}")
