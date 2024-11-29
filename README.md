# DataRobot Pre-Installation Script

This script automates the pre-installation and setup of DataRobot components, including downloading binaries, extracting files, loading container images, and pushing images to a container registry. The script is modular and allows for executing specific sections using the `--only` flag.

---

## Features

1. **Dependency Checks**:
   - Ensures required tools (`wget`, `tar`, `zstd`, `jq`, etc.) are installed.

2. **Utility Installation**:
   - Automatically installs missing utilities like `kubectl`, `helm`, and `docker/podman`.

3. **Modular Execution**:
   - Each step is modular and can be executed individually using the `--only` flag.

4. **Container Registry Support**:
   - Supports pushing container images to:
     - Generic Docker Registry
     - AWS ECR
     - Azure ACR
     - Google Artifact Registry (GAR)

5. **Error Logging**:
   - Logs all activities and errors to a log file in the `~/logs/` directory.

6. **Interactive Prompts**:
   - Prompts for essential inputs like DataRobot version, container runtime, and registry details.

---

## Installation

Clone or copy the script into a local file:
```bash
wget -O dr-pre.sh <script_url>
chmod +x dr-pre.sh
