import subprocess
import os
import sys
import requests
from tomlkit import parse
import inquirer

BRANCH = 'restructure/autora'


def create_python_environment():
    python_version = '{{ cookiecutter.python_version }}'
    # Get the project directory
    project_dir = os.path.join(os.path.realpath(os.path.curdir), 'researcher_environment')
    # Create a new virtual environment in the project directory
    venv_dir = os.path.join(project_dir, f'venv{python_version}')

    subprocess.run([f"python{python_version}", "-m", "venv", venv_dir], capture_output=True)

    # Install packages using pip and the requirements.txt file
    # Determine paths and commands based on the operating system
    if sys.platform == "win32":
        pip_exe = os.path.join(venv_dir, 'Scripts', 'pip')
        activate_command = os.path.join(venv_dir, 'Scripts', 'activate')
        print_message = f"\n\nProject setup is complete. To activate the virtual environment, run:\n\n{activate_command}\n\nOr if you're using PowerShell:\n\n. {activate_command}"
    else:
        pip_exe = os.path.join(venv_dir, 'bin', 'pip')
        activate_command = f"source {os.path.join(venv_dir, 'bin', 'activate')}"
        print_message = f"\n\nProject setup is complete. To activate the virtual environment, run:\n\n{activate_command}"

    response = requests.get(f'https://raw.githubusercontent.com/AutoResearch/autora/{BRANCH}/pyproject.toml')
    doc = parse(response.text)
    # Extract the list of dependencies from the 'all' section
    all_deps = doc["project"]["optional-dependencies"]["all"]

    # Remove the prefix and brackets from each dependency
    all_deps_clean = [s.split("[")[1].split("]")[0] for s in all_deps]

    additional_deps = []
    print(
        'In the following questions, mark the packages you want to install with >SPACE< and press >RETURN< to continue')
    for deps in all_deps_clean:
        type = deps.replace('all-', '')

        def article():
            return 'an' if type[0] in 'aeiou' else 'a'

        lst = doc["project"]["optional-dependencies"][deps]
        if lst != []:
            questions = [
                inquirer.Checkbox('choice',
                                  message=f"Do you want to install {type}",
                                  choices=lst,
                                  ),
            ]

            additional_deps += inquirer.prompt(questions)['choice']
    # Install packages using pip and the requirements.txt file
    requirements_file = os.path.join(project_dir, 'requirements.txt')
    with open(requirements_file, 'a') as f:
        for a in additional_deps:
            f.write(f'\n{a}')
    questions = [
        inquirer.List('prerelease',
                      message="Do you want to install the newest versions (Attention: Experimental!)?",
                      choices=['yes', 'no'],
                      ),
    ]

    answers = inquirer.prompt(questions)
    if answers['prerelease'] == 'yes':
        subprocess.run([pip_exe, "install", "--pre", "-r", requirements_file])
    else:
        subprocess.run([pip_exe, "install", "-r", requirements_file])


    # Print the content of the file

    # Print a message showing how to activate the virtual environment
    return print_message


msg_environment = create_python_environment()
print(msg_environment)