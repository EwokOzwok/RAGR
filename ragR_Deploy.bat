@echo off

rem Navigate to the directory
cd /d "C:\Users\Admin\Desktop\RAGR"

rem Build the Docker image
docker build -f "ragR-Dockerfile.txt" --progress=plain --no-cache -t ragr:5098 .

rem Start Docker Container
docker run -d --restart always --gpus all --name RAGR -p 5098:5098 ragr:5098


echo build completed.
