# ragR

## Overview
ragR is an R Shiny app with a Python backend, leveraging Retrieval-Augmented Generation (RAG) to enable interactive conversations with large PDF documents. The app integrates the **exlammav2** library for processing prompts and runs on **Windows Subsystem for Linux (WSL)**.

## Features
- Upload and interact with large **PDF** documents using **RAG**.
- Built with **shinyMobile** for a responsive, mobile-friendly UI.
- Backend powered by **Flask**, running on **port 5099**.
- Deployment scripts available to run the app via Docker on **port 5098**.
- Uses **exlammav2** for efficient text processing and response generation.

## Installation & Setup
### Prerequisites
- **Windows** with **WSL** enabled.
- **Docker** (if deploying via Docker).
- **R** and **R Shiny**.
- **Python** (with Flask and exlammav2 installed).

### Running the App Locally
1. Install the app via R:
   ```sh
   git clone https://github.com/ewokozwok/ragr.git
   cd ragr
   ```
2. Start the Flask backend:
   ```sh
   cd RAGR-master
   wsl
   activate exlammav2
   python General_RAG_PROCESSOR_5099.py
   ```
3. Install and Run the Shiny app:
   ```r
   remotes::install_github("EwokOzwok/RAGR")
   RAGR::run_app(options=list(port=5098))
   ```

### Running via Docker
1. Build and run the container:
   Double Click ragR_Deploy.bat

2. Access the app at `http://localhost:5098`.

## Screenshots
![Home Screen](screenshots/home.png)
![PDF Upload](screenshots/upload.png)
![Chat Interface](screenshots/chat.png)

## License
This project is licensed under the Apache License.

## Author
[Evan E. Ozmat](https://evanozmat.com/card)

